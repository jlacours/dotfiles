;;; init.el --- Juju's Emacs config -*- lexical-binding: t; -*-

;; --- Package manager + use-package ---
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(setq use-package-always-ensure t)

;; --- Load Secrets ---
(let ((secrets-file (locate-user-emacs-file "secrets.el")))
  (if (and secrets-file (file-exists-p secrets-file))
      (load secrets-file t)))

;; --- Keep machine-written customizations out of init.el ---
(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file))

;; --- Appearance overrides ---
(let ((appearance-file (locate-user-emacs-file "appearance.el")))
  (when (file-exists-p appearance-file)
    (load appearance-file nil t)))

;; --- UI basics ---
;; Let Wayland compositors size GUI frames exactly instead of rounding their
;; outer geometry to whole character-cell increments.
(setq frame-resize-pixelwise t)
(setq inhibit-startup-message t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(blink-cursor-mode 1)
(global-hl-line-mode 1)
(which-key-mode 1)
(fido-vertical-mode 1)
;; TAB completes to the highlighted candidate instead of popping *Completions*
(keymap-set icomplete-fido-mode-map "TAB" #'icomplete-force-complete)

;; Reload buffers when their files change on disk (like Neovim autoread)
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t
      ;; inotify only -- no 5s polling fallback (local fs, notifications work)
      auto-revert-avoid-polling t)

;; Relative line numbers (Neovim relativenumber muscle memory)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; Font + a little breathing room around the frame.
;; The frame alist sets the initial frame font, but markdown-mode's
;; code/pre/header faces inherit from `fixed-pitch' and `variable-pitch',
;; which ship with their own default families.  Pin every pitch face to
;; the same family so code blocks and inline code don't drift off
;; Comic Code.  Only :family/:height are touched, so the themes in
;; appearance.el still own the colours and hot-reload keeps working.
(let ((juju/font-family "Comic Code"))
  (add-to-list 'default-frame-alist
               (cons 'font (format "%s-10" juju/font-family)))
  (set-face-attribute 'default nil :family juju/font-family :height 100)
  (set-face-attribute 'fixed-pitch nil :family juju/font-family)
  (set-face-attribute 'variable-pitch nil :family juju/font-family))
(add-to-list 'default-frame-alist '(internal-border-width . 5))
(setq-default line-spacing 0.2)

;; Keep the cursor away from the window edges (like scrolloff)
(setq scroll-margin 8)

;; Spaces, not tabs
(setq-default indent-tabs-mode nil
              tab-width 2)

;; No backup / autosave clutter
(setq make-backup-files nil
      auto-save-default nil)

;; --- LLM Integration ---
(let ((llm-file (locate-user-emacs-file "llm.el")))
  (when (file-exists-p llm-file)
    (load llm-file nil t)))

;; --- Learning helpers ---
;; helper.el: C-c h spawns an LLM tutor that sees the current window
;; (visible text, modes, recent keys, *Messages*) via the gptel
;; backends from llm.el.  Loaded after llm.el on purpose.
(let ((helper-file (locate-user-emacs-file "helper.el")))
  (when (file-exists-p helper-file)
    (load helper-file nil t)))

;; tips.el: juju/tips-mode, a rotating fixed-width Emacs tip in the
;; mode-line (on by default; M-x juju/tips-mode toggles it).
(let ((tips-file (locate-user-emacs-file "tips.el")))
  (when (file-exists-p tips-file)
    (load tips-file nil t)))
