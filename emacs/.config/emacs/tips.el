;;; tips.el --- Rotating Emacs tips in the mode-line -*- lexical-binding: t; -*-

;;; Commentary:
;; `juju/tips-mode' (a global minor mode, on by default) appends ONE
;; fixed-width segment to the mode-line's misc-info area and rotates a
;; curated tip through it every few minutes.  Design constraints:
;;
;;   - The segment is ALWAYS exactly `juju/tips-width' columns (padded
;;     or truncated), so a new tip never pushes the neighbouring
;;     mode-line elements around.
;;   - In windows too narrow to afford it, the segment vanishes
;;     entirely instead of wrapping or squeezing anything.
;;   - The face inherits `shadow', so it stays dim and follows whatever
;;     theme appearance.el hot-reloads -- no hardcoded colors.
;;   - Toggling the mode off cancels the timer and removes the segment;
;;     nothing is left behind (check with M-x list-timers).
;;
;; Elisp syntax notes for the Neovim native:
;;   - `defface' defines a face (highlight group in vim terms).
;;   - `define-minor-mode' generates the mode variable, the toggle
;;     command, and runs its body each time the mode flips.
;;   - The mode-line is driven by a data structure (`mode-line-format');
;;     a `(:eval FORM)' element re-evaluates FORM on every redisplay.

;;; Code:

(defface juju/tips-mode-line
  '((t :inherit shadow))
  "Face for the rotating tip in the mode-line.
Inheriting from `shadow' keeps it dim in any theme, including the
wallust-generated ones appearance.el hot-reloads."
  :group 'mode-line-faces)

(defvar juju/tips-width 48
  "Exact width, in columns, of the tip segment.
Tips are truncated (with an ellipsis) or right-padded with spaces to
this width so rotation never reflows the mode-line.")

(defvar juju/tips-min-window-width 110
  "Hide the tip segment in windows narrower than this many columns.
Roughly `juju/tips-width' plus breathing room for the buffer name,
position, and mode indicators.  Hiding beats wrapping.")

(defvar juju/tips-interval 180
  "Seconds between tip rotations (180 = 3 minutes).")

(defvar juju/tips-list
  ["C-h k, then any key: what does it run?"
   "C-h f describes a function, C-h v a variable"
   "M-x runs any command by name, no keybind needed"
   "C-u 8 * inserts ******** (universal argument)"
   "F3 starts a keyboard macro, F4 ends & replays it"
   "C-x C-e evals the elisp sexp before point"
   "M-; comments the region, like gc in vim"
   "C-/ undoes; C-M-_ redoes"
   "C-SPC sets the mark, then move to select"
   "C-x C-x jumps between point and mark"
   "C-u C-SPC pops the mark ring: revisit old spots"
   "C-x r SPC marks a spot, C-x r j jumps back"
   "C-x r s / C-x r i: save / insert a register"
   "M-< / M-> = gg / G (buffer start / end)"
   "C-l recenters; press again for top, then bottom"
   "M-x ielm opens an elisp REPL to play in"
   "C-h m lists every key active in this buffer"
   "Pause after C-x or C-c: which-key shows the rest"
   "fido-vertical-mode: up/down arrows cycle candidates"
   "In the minibuffer, TAB completes the highlight"
   "C-j submits your literal input, not the highlighted match"
   "C-x b switches buffers, like :b in vim"
   "C-x C-b lists all buffers, like :ls"
   "C-s isearch; repeat C-s to jump to next match"
   "M-% query-replace: y/n per match, ! for all"
   "C-x o hops to the other window, like C-w w"
   "C-x 1 = :only, C-x 2 / C-x 3 = :sp / :vsp"
   "M-w copies; the kill-ring is a register history"
   "C-y pastes, then M-y cycles older kills in place"
   "C-k kills to end of line, like D"
   "M-x re-builder previews a regexp live"
   "C-x C-; comments just the current line"
   "C-h i opens the Info manuals, Emacs included"
   "M-m goes to first non-blank, like ^"
   "C-x z repeats the last command, like ."
   "C-h e shows the *Messages* buffer"
   "M-x apropos finds anything matching a word"
   "C-c h spawns your Emacs tutor (helper.el)"]
  "Curated tips for a Neovim native, shown one at a time.
A vector (square brackets) instead of a list: contents are constants
and `aref' does constant-time indexed access.")

;; -- Internal state.  The "--" infix marks these as private. ----------

(defvar juju/tips--index 0
  "Index into `juju/tips-list' of the tip currently displayed.")

(defvar juju/tips--timer nil
  "Timer object driving the rotation, nil when the mode is off.
Kept in a variable so toggling the mode off can `cancel-timer' it;
orphaned timers are the classic minor-mode leak.")

(defun juju/tips--segment ()
  "Return the mode-line segment string for the current tip.
Called from the mode-line on every redisplay, with the window being
drawn temporarily selected -- so `window-width' is per-window and
narrow splits hide the tip while wide windows keep it.
`truncate-string-to-width' both truncates (ELLIPSIS arg t) and pads
\(PADDING arg ?\\s, the space character) to an exact column count,
which is what guarantees the fixed footprint."
  (if (< (window-width) juju/tips-min-window-width)
      ""                                ; too narrow: hide, never wrap
    (concat
     "  "                               ; constant gap from the neighbours
     (propertize                        ; attach the dim face to the text
      (truncate-string-to-width (aref juju/tips-list juju/tips--index)
                                juju/tips-width nil ?\s t)
      'face 'juju/tips-mode-line))))

;; The symbol we splice into the mode-line.  Its value is a `(:eval ...)'
;; construct; marking the symbol "risky" is mandatory -- Emacs refuses to
;; eval mode-line code from unmarked variables (a security measure
;; against file-local variables injecting code).
(defvar juju/tips--mode-line-element
  '(:eval (juju/tips--segment))
  "Mode-line construct that renders the tip segment.")
(put 'juju/tips--mode-line-element 'risky-local-variable t)

(defun juju/tips--rotate ()
  "Advance to the next tip and refresh every mode-line.
`mod' wraps the index back to 0 past the end (circular rotation).
`force-mode-line-update' with argument t redraws all windows, not
just the selected one."
  (setq juju/tips--index (mod (1+ juju/tips--index)
                              (length juju/tips-list)))
  (force-mode-line-update t))

(define-minor-mode juju/tips-mode
  "Show a rotating, fixed-width Emacs tip in the mode-line.
The segment is exactly `juju/tips-width' columns so rotation never
shifts other mode-line elements, hides itself in narrow windows, and
rotates every `juju/tips-interval' seconds.  Toggling the mode off
cancels the timer and removes the segment."
  :global t                             ; one switch for all buffers
  :group 'mode-line
  (if juju/tips-mode
      (progn
        ;; Start at a random tip so every session opens differently.
        (setq juju/tips--index (random (length juju/tips-list)))
        ;; Append our element to the misc-info section (the mode-line
        ;; area conventionally used for extra indicators).  The final t
        ;; asks `add-to-list' to append rather than prepend, and
        ;; add-to-list never duplicates an existing element.
        (add-to-list 'mode-line-misc-info 'juju/tips--mode-line-element t)
        ;; Defensive: never stack a second timer if one already runs.
        (when (timerp juju/tips--timer)
          (cancel-timer juju/tips--timer))
        ;; run-with-timer DELAY REPEAT FUNCTION: first fire after one
        ;; interval, then repeat forever until cancelled.
        (setq juju/tips--timer
              (run-with-timer juju/tips-interval juju/tips-interval
                              #'juju/tips--rotate)))
    ;; Teardown mirrors setup exactly: remove the element, kill the
    ;; timer, and repaint so the segment disappears immediately.
    (setq mode-line-misc-info
          (delq 'juju/tips--mode-line-element mode-line-misc-info))
    (when (timerp juju/tips--timer)
      (cancel-timer juju/tips--timer))
    (setq juju/tips--timer nil))
  (force-mode-line-update t))

;; On by default; M-x juju/tips-mode toggles it off (and back on).
(juju/tips-mode 1)

(provide 'tips)
;;; tips.el ends here
