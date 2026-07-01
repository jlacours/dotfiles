;;; helper.el --- Spawnable Emacs tutor that sees what you see -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-c h' (`juju/emacs-tutor') opens an LLM tutor chat in a side window.
;; Unlike a blind chatbot, the tutor receives a snapshot of your current
;; environment: the text visible in the selected window, the buffer name,
;; major/minor modes, cursor position, your last ~30 keystrokes, and the
;; tail of *Messages*.  It talks through the gptel backends already
;; configured in llm.el (local llama.cpp by default; switch with `C-c g').
;;
;; The tutor also gets four READ-ONLY tools so it can look things up in
;; your running Emacs instead of hallucinating: describe_function,
;; describe_variable, describe_key and apropos_symbols.  Nothing the
;; model sends is ever evaluated as code.
;;
;; Elisp syntax notes for the Neovim native reading along:
;;   - `defvar' declares a global variable (like a vim g: variable).
;;   - A name like `juju/tutor--snapshot' is just a convention: the
;;     "juju/" prefix namespaces it, and "--" marks it as private.
;;   - `let*' binds local variables in order, each one able to use the
;;     previous ones (plain `let' binds them all "in parallel").
;;   - `(interactive)' is what turns a function into a command you can
;;     run with M-x or bind to a key -- like a :command in vim.

;;; Code:

;; Tell the byte-compiler these come from gptel without loading it now.
;; `declare-function' is compile-time only: it silences "function not
;; known" warnings.  The empty `defvar's do the same for variables --
;; a `defvar' with no value just says "this name is a dynamic variable",
;; it does not set anything.  gptel itself is only loaded the first
;; time the tutor is actually spawned (see `require' in the command).
(declare-function gptel "gptel")
(declare-function gptel-make-tool "gptel-request")
(defvar gptel-tools)
(defvar gptel-system-prompt)
(defvar gptel--system-message)          ; pre-0.9.9.6 name, kept as fallback

(defvar juju/tutor-buffer-name "*emacs-tutor*"
  "Name of the tutor chat buffer.")

(defvar juju/tutor-window-side 'right
  "Which side of the frame the tutor window opens on.
One of the symbols `right' or `bottom'.")

(defvar juju/tutor-system-prompt
  (concat
   "You are an Emacs tutor running inside the student's own Emacs. "
   "The student is a long-time Neovim user learning Emacs step by step.\n\n"
   "Each message may start with a snapshot of what the student currently "
   "sees: the visible window text, buffer and modes, cursor position, "
   "recent keystrokes, and recent *Messages* output. Use it -- refer to "
   "what is actually on their screen.\n\n"
   "Teaching style:\n"
   "- Explain one idea at a time, step by step.\n"
   "- When you show Emacs Lisp, explain the syntax itself (what defun, "
   "let, setq, quote, lambda etc. do), not just the effect.\n"
   "- Relate concepts to Neovim equivalents when helpful "
   "(kill-ring vs registers, C-g vs <Esc>, keyboard macros vs q-recording).\n"
   "- Give the real key sequences in Emacs notation (C-x C-f, M-x).\n\n"
   "You have READ-ONLY tools to inspect this Emacs: describe_function, "
   "describe_variable, describe_key and apropos_symbols. Use them instead "
   "of guessing when unsure. You cannot evaluate code or change anything.\n\n"
   "Be concise. Prefer short answers the student can try immediately.")
  "System prompt (persona) given to the tutor LLM.")

(defvar juju/tutor--source-buffer nil
  "The buffer `juju/emacs-tutor' was last invoked from.
The describe_key tool looks keys up here, so bindings are resolved
in the buffer you were actually working in, not in the chat buffer.")

;; --- Snapshot helpers -------------------------------------------------
;; Each returns a plain string; `juju/tutor--snapshot' glues them together.

(defun juju/tutor--visible-text ()
  "Return the text currently visible in the selected window.
`window-start' and `window-end' give buffer positions of the first and
last visible characters; a non-nil second argument to `window-end'
asks for an up-to-date value.  `buffer-substring-no-properties'
extracts the text between two positions, stripped of fontification."
  (buffer-substring-no-properties
   (window-start)
   (window-end nil t)))

(defun juju/tutor--minor-modes ()
  "Return the names of active minor modes as one comma-separated string.
`minor-mode-list' holds every minor mode Emacs knows about; a mode is
active when its variable is bound and non-nil.  `dolist' is elisp's
foreach; `push' prepends to a list, so we `nreverse' at the end."
  (let ((active '()))
    (dolist (mode minor-mode-list)
      (when (and (boundp mode) (symbol-value mode))
        (push (symbol-name mode) active)))
    (mapconcat #'identity (nreverse active) ", ")))

(defun juju/tutor--recent-keys ()
  "Return the last 30 keystrokes as a human-readable string.
`recent-keys' is Emacs's lossage: a vector of the last 300 input
events.  `substring' works on vectors too, and `key-description'
renders events in the familiar control/meta key notation."
  (let* ((keys (recent-keys))
         (len (length keys))
         (start (max 0 (- len 30))))
    (key-description (substring keys start))))

(defun juju/tutor--messages-tail ()
  "Return the last 15 lines of the *Messages* buffer.
`with-current-buffer' temporarily switches buffers, like :b in vim but
scoped to the parenthesised block.  `save-excursion' restores point
afterwards so we never disturb the real *Messages* position."
  (with-current-buffer (messages-buffer)
    (save-excursion
      (goto-char (point-max))
      (forward-line -15)                ; negative = move backwards
      (buffer-substring-no-properties (point) (point-max)))))

(defun juju/tutor--snapshot ()
  "Assemble the full environment snapshot as a markdown string.
Must be called with the buffer/window you want captured still
selected, i.e. before the chat buffer is displayed.
Four-backtick fences are used so buffers containing ``` do not
break the markdown structure."
  (format
   (concat
    "Here is what I currently see in Emacs (snapshot taken just now):\n\n"
    "- Buffer: `%s` (major mode: `%s`)\n"
    "- Cursor: line %d, column %d (buffer has %d lines)%s\n"
    "- Active minor modes: %s\n"
    "- Recent keystrokes (oldest to newest): `%s`\n\n"
    "Visible window text:\n\n````text\n%s\n````\n\n"
    "Recent *Messages*:\n\n````text\n%s````\n\n"
    "My question: ")
   (buffer-name)
   major-mode
   (line-number-at-pos)
   (current-column)
   (count-lines (point-min) (point-max))
   ;; Mention the region only when one is active.  `if' returns a value
   ;; (everything in elisp is an expression), so it can sit mid-format.
   (if (use-region-p)
       (format " -- region active: %d chars selected"
               (- (region-end) (region-beginning)))
     "")
   (juju/tutor--minor-modes)
   (juju/tutor--recent-keys)
   (juju/tutor--visible-text)
   (juju/tutor--messages-tail)))

;; --- Read-only introspection tools ------------------------------------
;; These let the model *look at* the running Emacs.  Everything funnels
;; through the standard describe-* help commands or `apropos-internal';
;; no model-provided code is ever evaluated.

(defun juju/tutor--help-text (thunk)
  "Run THUNK (a zero-argument help command) and return the *Help* text.
`save-window-excursion' snapshots the window layout and restores it
afterwards, so the help window never actually appears on screen.
`funcall' calls a function value -- needed because THUNK arrived in a
variable rather than being written literally at the call site."
  (save-window-excursion
    (let ((help-window-select nil))
      (funcall thunk)
      (with-current-buffer (help-buffer)
        (buffer-substring-no-properties (point-min) (point-max))))))

(defun juju/tutor--tool-describe-function (name)
  "Return the full help text for the function named NAME.
`intern-soft' looks a name up in the symbol table WITHOUT creating it
\(plain `intern' would); it returns nil for unknown names."
  (let ((sym (intern-soft name)))
    (if (and sym (fboundp sym))         ; fboundp: has a function definition?
        (juju/tutor--help-text (lambda () (describe-function sym)))
      (format "No function named `%s' is defined in this Emacs." name))))

(defun juju/tutor--tool-describe-variable (name)
  "Return the full help text for the variable named NAME."
  (let ((sym (intern-soft name)))
    (if (and sym (boundp sym))          ; boundp: has a value as a variable?
        (juju/tutor--help-text (lambda () (describe-variable sym)))
      (format "No variable named `%s' is bound in this Emacs." name))))

(defun juju/tutor--tool-describe-key (keys)
  "Return what the key sequence KEYS is bound to.
KEYS uses `kbd' notation (control-x control-f is written \"C-x C-f\",
meta-w is \"M-w\").  The lookup runs in the buffer the tutor was
spawned from, because key bindings are buffer-dependent (major/minor
mode maps).  `condition-case' is elisp's try/catch: bad input makes
`kbd' signal an error, which we turn into a readable string for the
model instead of crashing the tool call."
  (condition-case err
      (with-current-buffer (if (buffer-live-p juju/tutor--source-buffer)
                               juju/tutor--source-buffer
                             (current-buffer))
        (let ((cmd (key-binding (kbd keys))))
          (cond
           ((null cmd)
            (format "%s is not bound to anything in buffer %s."
                    keys (buffer-name)))
           ((commandp cmd)
            (format "%s runs the command `%s'.\n\n%s"
                    keys cmd
                    (or (documentation cmd) "(no documentation)")))
           (t (format "%s is bound to: %S" keys cmd)))))
    (error (format "Could not look up %s: %s"
                   keys (error-message-string err)))))

(defun juju/tutor--tool-apropos (pattern)
  "Return symbols matching regexp PATTERN, tagged and capped at 100.
`apropos-internal' returns matching symbols without any UI.
`seq-take' returns at most N elements (no error on short lists)."
  (let ((matches (apropos-internal pattern)))
    (if (null matches)
        (format "No symbols match \"%s\"." pattern)
      (mapconcat
       (lambda (sym)
         (format "%s (%s)" sym
                 (cond ((commandp sym) "command")
                       ((fboundp sym) "function")
                       ((boundp sym) "variable")
                       (t "symbol"))))
       (seq-take matches 100) "\n"))))

(defvar juju/tutor--tools nil
  "Cached list of gptel tool objects for the tutor buffer.")

(defun juju/tutor--make-tools ()
  "Build (once) and return the tutor's read-only gptel tools.
`or' returns its first non-nil argument, so after the first call the
cached list is reused.  Each `gptel-make-tool' registers the tool with
gptel and returns a tool object; :args describes the parameters in
JSON-schema terms so the model knows how to call it."
  (or juju/tutor--tools
      (setq juju/tutor--tools
            (list
             (gptel-make-tool
              :name "describe_function"
              :function #'juju/tutor--tool-describe-function
              :description "Look up an Emacs Lisp function or command by name and return its full documentation, signature and source location. Read-only."
              :args '((:name "name" :type string
                       :description "Function name, e.g. \"find-file\""))
              :category "emacs-introspection")
             (gptel-make-tool
              :name "describe_variable"
              :function #'juju/tutor--tool-describe-variable
              :description "Look up an Emacs Lisp variable by name and return its documentation and current value. Read-only."
              :args '((:name "name" :type string
                       :description "Variable name, e.g. \"fill-column\""))
              :category "emacs-introspection")
             (gptel-make-tool
              :name "describe_key"
              :function #'juju/tutor--tool-describe-key
              :description "Find what command a key sequence runs in the buffer the student is working in. Read-only."
              :args '((:name "keys" :type string
                       :description "Key sequence in kbd notation, e.g. \"C-x C-f\" or \"M-w\""))
              :category "emacs-introspection")
             (gptel-make-tool
              :name "apropos_symbols"
              :function #'juju/tutor--tool-apropos
              :description "Search all Emacs symbols (commands, functions, variables) whose name matches a regexp. Returns up to 100 matches. Read-only."
              :args '((:name "pattern" :type string
                       :description "Regexp to match symbol names, e.g. \"window.*split\""))
              :category "emacs-introspection")))))

;; --- The command -------------------------------------------------------

(defun juju/emacs-tutor ()
  "Open an LLM tutor chat that can see the current window.
Snapshots the visible text, modes, recent keys and *Messages* tail,
then opens (or reuses) a gptel chat in a side window with the snapshot
pre-inserted, a tutor persona, and read-only introspection tools."
  (interactive)
  ;; Load gptel lazily -- keeps startup fast; the use-package stanza in
  ;; llm.el configures the backends the moment the feature loads.
  (require 'gptel)
  (when (eq (current-buffer) (get-buffer juju/tutor-buffer-name))
    (user-error "You are already in the tutor buffer -- just ask below"))
  (setq juju/tutor--source-buffer (current-buffer))
  ;; Take the snapshot FIRST, while the window we want captured is still
  ;; selected; creating the chat buffer must not pollute it.
  (let* ((snapshot (juju/tutor--snapshot))
         ;; `gptel' (the function) creates or reuses a chat buffer with
         ;; gptel-mode on, and returns it without displaying it.
         (buf (gptel juju/tutor-buffer-name)))
    (with-current-buffer buf
      ;; Buffer-local persona: `setq-local' sets the variable only in
      ;; this buffer (like vim's setlocal), so other gptel chats keep
      ;; the default system prompt.  gptel renamed the variable in
      ;; 0.9.9.6; support both names via a runtime `boundp' check.
      (if (boundp 'gptel-system-prompt)
          (setq-local gptel-system-prompt juju/tutor-system-prompt)
        ;; `with-suppressed-warnings' tells the byte-compiler "yes, I know
        ;; this is obsolete, that's the point of this fallback branch" --
        ;; without it, every compile prints a warning even though the
        ;; `boundp' check above means this line only runs on old gptel.
        (with-suppressed-warnings ((obsolete gptel--system-message))
          (setq-local gptel--system-message juju/tutor-system-prompt)))
      ;; Hand the tutor its read-only tools, again buffer-locally.
      (setq-local gptel-tools (juju/tutor--make-tools))
      ;; Append the snapshot at the end of the conversation.  On a fresh
      ;; buffer gptel has already inserted its prompt prefix; on reuse we
      ;; land after the previous exchange, starting a new turn.
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))     ; bolp: at beginning of line?
      (insert snapshot))
    ;; Show it in a side window and jump in.  The nested-list argument is
    ;; a standard `display-buffer' "action": which function to use, then
    ;; parameters for it.
    (select-window
     (display-buffer buf
                     `((display-buffer-in-side-window)
                       (side . ,juju/tutor-window-side)
                       (window-width . 0.45)    ; used when side = right
                       (window-height . 0.4)))) ; used when side = bottom
    (goto-char (point-max))
    (message "Ask your question, then send with C-c RET")))

;; `keymap-global-set' is the modern (Emacs 29+) global bind, same
;; family as the `keymap-set' already used in init.el.  C-c <letter> is
;; reserved for users, and C-c h is free in this config (C-c g = gptel).
(keymap-global-set "C-c h" #'juju/emacs-tutor)

(provide 'helper)
;;; helper.el ends here
