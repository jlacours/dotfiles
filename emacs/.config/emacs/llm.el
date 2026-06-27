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
        gptel-model 'qwen3.6-35b-a3b))
