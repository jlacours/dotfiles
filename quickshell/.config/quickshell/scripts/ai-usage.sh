#!/usr/bin/env bash
# Unified AI-subscription usage reporter for the quickshell bar.
#
# Emits a single JSON object describing usage for three providers:
#   claude — Claude Code 5h rolling block via `ccusage` (cost/tokens/projection)
#   codex  — ChatGPT (Codex CLI) primary/secondary rate-limit windows
#   zai    — z.ai GLM coding-plan 5h + weekly token quotas (+ monthly MCP)
#
# Each provider carries an `ok` flag so the UI can degrade gracefully.
# All reset timestamps are normalised to epoch SECONDS.

set -uo pipefail

# Quickshell launches us with a slim PATH; make sure the usual bins resolve.
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"

now=$(date +%s)

# ─────────────────────────── Claude (real subscription %) ────────────────────
# The exact source Claude Code's /usage uses: the OAuth-token usage endpoint.
# Gives true 5h + 7-day utilisation. ccusage (offline, fast) adds cost/token
# detail for the panel. The token is refreshed by Claude Code itself.
claude='{"ok":false}'
# The /oauth/usage endpoint is rate-limited, so cache it (5 min TTL) and fall
# back to the last good value on failure rather than blanking the readout.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ai-usage"
mkdir -p "$cache_dir" 2>/dev/null
oauth_cache="$cache_dir/claude-oauth.json"
oauth_ttl=300

base=""
if [ -f "$oauth_cache" ]; then
  age=$(( now - $(stat -c %Y "$oauth_cache" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$oauth_ttl" ] && base=$(cat "$oauth_cache" 2>/dev/null)
fi

if [ -z "$base" ]; then
  creds="$HOME/.claude/.credentials.json"
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
  sub=$(jq -r '.claudeAiOauth.subscriptionType // empty' "$creds" 2>/dev/null)
  if [ -n "$tok" ]; then
    u=$(curl -s -m 10 \
      -H "Authorization: Bearer $tok" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    fetched=$(printf '%s' "$u" | jq -c --arg sub "$sub" '
      def iso2s: if . == null then null
                 else (try (sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601) catch null) end;
      if (.five_hour.utilization != null) or (.seven_day.utilization != null) then
        { ok: true,
          plan:      ($sub // null),
          pct5h:     (.five_hour.utilization // null),
          reset5h:   (.five_hour.resets_at | iso2s),
          pctWeek:   (.seven_day.utilization // null),
          resetWeek: (.seven_day.resets_at | iso2s) }
      else empty end' 2>/dev/null)
    if [ -n "$fetched" ]; then
      base="$fetched"
      printf '%s' "$base" > "$oauth_cache"
    fi
  fi
  # Fetch failed (rate-limited / expired token): reuse stale cache if we have it.
  [ -z "$base" ] && [ -f "$oauth_cache" ] && base=$(cat "$oauth_cache" 2>/dev/null)
fi
[ -n "$base" ] && claude="$base"

# Cost/token/projection detail for the active block (offline = fast, ~100ms).
cc=$(bunx ccusage blocks --json --offline 2>/dev/null | jq -c '
  ([.blocks[] | select(.isActive == true)][0]) as $b
  | if $b == null then {}
    else { cost: ($b.costUSD // null), tokens: ($b.totalTokens // null),
           projCost: ($b.projection.totalCost // null), projTokens: ($b.projection.totalTokens // null),
           burnPerHour: ($b.burnRate.costPerHour // null), remainingMin: ($b.projection.remainingMinutes // null),
           models: ($b.models // []) } end' 2>/dev/null)
[ -z "$cc" ] && cc='{}'
claude=$(jq -nc --argjson a "$claude" --argjson b "$cc" \
  '$a + (if ($a.ok // false) then $b else {} end)' 2>/dev/null || printf '%s' "$claude")

# ───────────────────── Codex / ChatGPT (rate-limit windows) ──────────────────
codex='{"ok":false}'
codex_file=$(find "$HOME/.codex/sessions" -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | awk '{print $2}' \
  | while read -r f; do
      if grep -ql '"rate_limits"' "$f" 2>/dev/null; then echo "$f"; break; fi
    done)
if [ -n "${codex_file:-}" ]; then
  asof=$(stat -c %Y "$codex_file" 2>/dev/null || echo "$now")
  rl=$(jq -c 'recurse | objects | select(has("rate_limits")) | .rate_limits' \
        "$codex_file" 2>/dev/null | tail -1)
  if [ -n "${rl:-}" ] && [ "$rl" != "null" ]; then
    parsed=$(printf '%s' "$rl" | jq -c --argjson asof "$asof" '
      { ok: true,
        plan:       (.plan_type // null),
        pct5h:      (.primary.used_percent // null),
        reset5h:    (.primary.resets_at // null),
        win5hMin:   (.primary.window_minutes // null),
        pctWeek:    (.secondary.used_percent // null),
        resetWeek:  (.secondary.resets_at // null),
        winWeekMin: (.secondary.window_minutes // null),
        asOf:       $asof }' 2>/dev/null)
    [ -n "$parsed" ] && codex="$parsed"
  fi
fi

# ───────────────────────── z.ai (GLM coding plan) ────────────────────────────
zai='{"ok":false}'
# Quickshell won't have ZAI_API_KEY in its env; pull it from ~/.zshenv if needed.
if [ -z "${ZAI_API_KEY:-}" ] && [ -f "$HOME/.zshenv" ]; then
  ZAI_API_KEY=$(grep -E "^[[:space:]]*export[[:space:]]+ZAI_API_KEY=" "$HOME/.zshenv" \
    | head -1 | sed -E "s/^[^=]*=//; s/^[[:space:]]*['\"]//; s/['\"].*$//")
fi
if [ -n "${ZAI_API_KEY:-}" ]; then
  zraw=$(curl -s -m 10 -H "Authorization: Bearer $ZAI_API_KEY" \
    "https://api.z.ai/api/monitor/usage/quota/limit" 2>/dev/null)
  if [ -n "$zraw" ]; then
    parsed=$(printf '%s' "$zraw" | jq -c '
      def ms2s: if . == null then null else (./1000 | floor) end;
      if (.success == true) and (.data.limits | type == "array") then
        ([.data.limits[] | select(.type == "TOKENS_LIMIT")] | sort_by(.nextResetTime)) as $tok
        | ([.data.limits[] | select(.type == "TIME_LIMIT")]) as $mcp
        | { ok: true,
            level:    (.data.level // null),
            pct5h:    ($tok[0].percentage // null),
            reset5h:  ($tok[0].nextResetTime // null | ms2s),
            pctWeek:  ($tok[1].percentage // null),
            resetWeek:($tok[1].nextResetTime // null | ms2s),
            mcpPct:   ($mcp[0].percentage // null),
            mcpReset: ($mcp[0].nextResetTime // null | ms2s) }
      else { ok: false } end' 2>/dev/null)
    [ -n "$parsed" ] && zai="$parsed"
  fi
fi

# ───────────────────────── OpenRouter (prepaid credits) ─────────────────────
openrouter='{"ok":false}'
if [ -z "${OPENROUTER_API_KEY:-}" ] && [ -f "$HOME/.zshenv" ]; then
  OPENROUTER_API_KEY=$(grep -E "^[[:space:]]*export[[:space:]]+OPENROUTER_API_KEY=" "$HOME/.zshenv" \
    | head -1 | sed -E "s/^[^=]*=//; s/^[[:space:]]*['\"]//; s/['\"].*$//")
fi
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  cr=$(curl -s -m 10 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/credits" 2>/dev/null)
  base=$(printf '%s' "$cr" | jq -c '
    .data as $c
    | if ($c.total_credits == null) then { ok: false }
      else ($c.total_credits - ($c.total_usage // 0)) as $rem
        | { ok: true,
            remaining: $rem,
            total: $c.total_credits,
            used: ($c.total_usage // 0),
            pctRemaining: (if $c.total_credits > 0 then ($rem / $c.total_credits * 100) else null end) }
      end' 2>/dev/null)
  if [ -n "$base" ]; then
    openrouter="$base"
    # Enrich with per-key usage windows if the key endpoint answers.
    ky=$(curl -s -m 10 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      "https://openrouter.ai/api/v1/key" 2>/dev/null)
    enr=$(printf '%s' "$ky" | jq -c '.data | {
        keyUsage:   (.usage // null),
        keyDaily:   (.usage_daily // null),
        keyWeekly:  (.usage_weekly // null),
        keyMonthly: (.usage_monthly // null) }' 2>/dev/null)
    if [ -n "$enr" ] && [ "$enr" != "null" ]; then
      openrouter=$(jq -nc --argjson a "$openrouter" --argjson b "$enr" \
        '$a + (if ($a.ok // false) then $b else {} end)' 2>/dev/null || printf '%s' "$openrouter")
    fi
  fi
fi

# ─────────────────────────────── assemble ───────────────────────────────────
jq -nc \
  --argjson now "$now" \
  --argjson claude "$claude" \
  --argjson codex "$codex" \
  --argjson zai "$zai" \
  --argjson openrouter "$openrouter" \
  '{ now: $now, claude: $claude, codex: $codex, zai: $zai, openrouter: $openrouter }'
