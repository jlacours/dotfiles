;;; appearance.el --- Juju's Emacs appearance overrides -*- lexical-binding: t; -*-

;; Theme stack: misterioso as the base, then ONE of two overlays on top:
;;   - `juju'      -- wallust-generated from the wallpaper
;;                    (~/.cache/wallust/juju-theme.el, hot-reloaded)
;;   - `juju-gold' -- the hand-tuned near-black/gold fallback, used until
;;                    wallust has rendered at least once
;; Both are real custom themes (not set-face-attribute calls) so they can
;; be enabled/disabled cleanly; direct attribute overrides would outrank
;; every theme and make hot-reload impossible.

(require 'filenotify)

(mapc #'disable-theme custom-enabled-themes)
(load-theme 'misterioso t)

;; --- Gold fallback: near-black with rationed gold accents ---
;; Gold only at focal points (cursor, prompt, keywords, functions);
;; everything high-area (body text, variables, chrome) stays neutral so
;; the buffer doesn't read as one amber wash.
(deftheme juju-gold
  "Near-black with gold accents; fallback until wallust renders.")

(let ((bg      "#0b0a07")   ; warm near-black
      (bg-soft "#15130c")   ; current line
      (fg      "#cfc8b8")   ; neutral warm gray -- deliberately NOT gold
      (fg-dim  "#8c8676")
      (gold    "#e3c478")   ; the identity color: cursor, prompts, accents
      (amber   "#e09e4e")   ; keywords
      (cream   "#f1da9b")   ; function names
      (tan     "#bfae90")   ; variables -- quiet, near-neutral
      (sage    "#a8b386")   ; strings
      (teal    "#8fb3a3")   ; types / links
      (copper  "#cf8a5b")   ; constants / builtins
      (comment "#6c665a")
      (region  "#332a16"))

  (custom-theme-set-faces
   'juju-gold
   ;; Frame chrome
   `(default ((t (:background ,bg :foreground ,fg))))
   `(cursor ((t (:background ,gold))))
   `(fringe ((t (:background ,bg))))
   `(internal-border ((t (:background ,bg))))
   `(vertical-border ((t (:foreground ,bg :background ,bg))))
   `(mode-line ((t (:background "#191711" :foreground ,fg
                    :box (:line-width 1 :color "#2b2820")))))
   `(mode-line-inactive ((t (:background "#100f0b" :foreground ,fg-dim
                             :box (:line-width 1 :color "#1d1b16")))))
   `(minibuffer-prompt ((t (:foreground ,gold :weight bold))))
   ;; Editing aids
   `(hl-line ((t (:background ,bg-soft))))
   `(region ((t (:background ,region))))
   `(line-number ((t (:background ,bg :foreground "#534f43"))))
   `(line-number-current-line ((t (:background ,bg-soft :foreground ,gold))))
   `(show-paren-match ((t (:background "#3a2f12" :foreground ,gold :weight bold))))
   `(isearch ((t (:background ,gold :foreground ,bg))))
   `(lazy-highlight ((t (:background "#4a3c18" :foreground ,fg))))
   `(link ((t (:foreground ,teal :underline t))))
   ;; Syntax: gold family only where emphasis belongs
   `(font-lock-comment-face ((t (:foreground ,comment :slant italic))))
   `(font-lock-doc-face ((t (:foreground "#7a7465" :slant italic))))
   `(font-lock-keyword-face ((t (:foreground ,amber :weight semi-bold))))
   `(font-lock-string-face ((t (:foreground ,sage))))
   `(font-lock-function-name-face ((t (:foreground ,cream))))
   `(font-lock-variable-name-face ((t (:foreground ,tan))))
   `(font-lock-type-face ((t (:foreground ,teal))))
   `(font-lock-constant-face ((t (:foreground ,copper))))
   `(font-lock-builtin-face ((t (:foreground ,copper :slant italic))))))

;; --- Wallust theme + hot reload ---
(defvar juju/wallust-theme-file
  (expand-file-name "~/.cache/wallust/juju-theme.el")
  "Theme rendered by wallust; see [templates] in ~/.config/wallust/wallust.toml.")

(add-to-list 'custom-theme-load-path
             (file-name-directory juju/wallust-theme-file))

(defun juju/apply-theme ()
  "Enable the wallust `juju' theme if rendered, else the `juju-gold' fallback."
  (if (file-exists-p juju/wallust-theme-file)
      (progn
        (disable-theme 'juju-gold)
        ;; disable before load so a re-render fully replaces the old colors
        (disable-theme 'juju)
        (load-theme 'juju t))
    (enable-theme 'juju-gold)))

(defvar juju/wallust--reload-timer nil)

(defun juju/wallust--theme-changed (event)
  "Re-apply the theme when a filenotify EVENT touches the rendered file."
  ;; EVENT is (DESCRIPTOR ACTION FILE [FILE1]); wallust may replace the file
  ;; via rename, so match the name against both FILE slots.
  (when (seq-some (lambda (f)
                    (and (stringp f)
                         (string= (file-name-nondirectory f)
                                  (file-name-nondirectory juju/wallust-theme-file))))
                  (nthcdr 2 event))
    ;; debounce: one render can fire several events
    (when (timerp juju/wallust--reload-timer)
      (cancel-timer juju/wallust--reload-timer))
    (setq juju/wallust--reload-timer
          (run-with-idle-timer 0.3 nil #'juju/apply-theme))))

(defvar juju/wallust--watch
  (let ((dir (file-name-directory juju/wallust-theme-file)))
    (when (file-directory-p dir)
      (file-notify-add-watch dir '(change) #'juju/wallust--theme-changed)))
  "Directory watch that hot-reloads the theme after wallust renders.")

(juju/apply-theme)
