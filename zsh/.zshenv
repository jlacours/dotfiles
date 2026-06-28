# Aider against the Z.AI GLM Coding Plan. Key is passed from $ZAI_API_KEY
# at runtime, so it never gets written into aider's config files.
aider-glm()     { aider --model openai/glm-4.6     --openai-api-base https://api.z.ai/api/coding/paas/v4 --openai-api-key "$ZAI_API_KEY" "$@"; }
aider-glm-air() { aider --model openai/glm-4.5-air --openai-api-base https://api.z.ai/api/coding/paas/v4 --openai-api-key "$ZAI_API_KEY" "$@"; }

[[ -f ~/.zshenv.local ]] && source ~/.zshenv.local
