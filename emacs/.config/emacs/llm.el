;;; llm.el --- Juju's Emacs LLM integration -*- lexical-binding: t; -*-

(use-package gptel
  :bind ("C-c g" . gptel-menu)
  :config
  ;; Local llama.cpp: Connected to the systemd-managed service on :3002.
  ;; Only the model actually loaded into the server is listed here.
  (defvar my/llama-cpp
    (gptel-make-openai "llama.cpp"
      :host "localhost:3002"
      :protocol "http"
      :stream t
      :key "no-key"
      :models '(qwen3.6-35b-a3b)))

  ;; OpenRouter.
  (defvar my/openrouter
    (gptel-make-openai "OpenRouter"
      :host "openrouter.ai"
      :endpoint "/api/v1/chat/completions"
      :stream t
      :key gptel-key-openrouter
      :models '(deepseek/deepseek-v4-flash openai/gpt-4o)))

  ;; OpenAI.
  (defvar my/openai
    (gptel-make-openai "OpenAI"
      :host "api.openai.com"
      :endpoint "/v1/chat/completions"
      :stream t
      :key gptel-key-openai
      :models '(gpt-4o)))

  ;; Set defaults.
  (setq gptel-backend my/llama-cpp
        gptel-model 'qwen3.6-35b-a3b
        gptel-default-mode 'markdown-mode
        markdown-fontify-code-blocks-natively t
        ;; Keep model reasoning enabled, but divert it from the chat UI.
        gptel-include-reasoning " *gptel-reasoning*")

  ;; Follow streamed responses when they continue below the viewport.
  (add-hook 'gptel-post-stream-hook #'gptel-auto-scroll)

  ;; Animate gptel's header-line status while a request is in flight.
  (defconst juju/gptel-spinner-frames
    ["⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"])

  (defvar-local juju/gptel-spinner-timer nil)
  (defvar-local juju/gptel-spinner-frame 0)
  (defvar juju/gptel-spinner-rendering nil)

  (defun juju/gptel-spinner-stop ()
    "Stop the current gptel buffer's activity spinner."
    (when (timerp juju/gptel-spinner-timer)
      (cancel-timer juju/gptel-spinner-timer))
    (setq juju/gptel-spinner-timer nil
          juju/gptel-spinner-frame 0))

  (defun juju/gptel-spinner-tick (buffer)
    "Advance the gptel activity spinner in BUFFER."
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and gptel-mode (timerp juju/gptel-spinner-timer))
          (let ((juju/gptel-spinner-rendering t)
                (frame (aref juju/gptel-spinner-frames
                             juju/gptel-spinner-frame)))
            (setq juju/gptel-spinner-frame
                  (% (1+ juju/gptel-spinner-frame)
                     (length juju/gptel-spinner-frames)))
            (gptel--update-status
             (format " %s Thinking…" frame)
             'warning))))))

  (defun juju/gptel-spinner-start ()
    "Start the current gptel buffer's activity spinner."
    (unless (timerp juju/gptel-spinner-timer)
      (setq juju/gptel-spinner-timer
            (run-at-time 0 0.12 #'juju/gptel-spinner-tick
                         (current-buffer)))))

  (defun juju/gptel-spinner-follow-status (message &optional _face)
    "Start or stop the spinner after gptel reports status MESSAGE."
    (unless juju/gptel-spinner-rendering
      (if (member message '(" Waiting..." " Typing..."))
          (juju/gptel-spinner-start)
        (juju/gptel-spinner-stop))))

  (defun juju/gptel-spinner-mode-setup ()
    "Clean up the spinner when a gptel buffer is disabled or killed."
    (if gptel-mode
        (add-hook 'kill-buffer-hook #'juju/gptel-spinner-stop nil t)
      (juju/gptel-spinner-stop)))

  ;; Keep reloads idempotent when llm.el is evaluated more than once.
  (advice-remove 'gptel--update-status #'juju/gptel-spinner-follow-status)
  (advice-add 'gptel--update-status :after
              #'juju/gptel-spinner-follow-status)
  (add-hook 'gptel-mode-hook #'juju/gptel-spinner-mode-setup))
