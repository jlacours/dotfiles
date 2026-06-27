#!/usr/bin/env bash

set -uo pipefail

readonly REDACT='[REDACTED]'
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'error: not inside a Git repository\n' >&2
  exit 2
}

cd "$repo" || exit 2

if [[ "$(basename "$repo")" != ".dotfiles" ]]; then
  printf 'error: expected the .dotfiles repository, got %s\n' "$repo" >&2
  exit 2
fi

declare -A seen=()
files=()

add_file() {
  local path="$1"
  [[ -n "$path" && -f "$path" && ! -L "$path" ]] || return 0
  [[ -v "seen[$path]" ]] && return 0
  seen["$path"]=1
  files+=("$path")
}

while IFS= read -r -d '' path; do
  add_file "$path"
done < <(git diff --name-only -z HEAD --)

while IFS= read -r -d '' path; do
  add_file "$path"
done < <(git ls-files --others --exclude-standard -z)

if (( ${#files[@]} == 0 )); then
  printf 'audit: no changed or untracked files\n'
  exit 0
fi

findings=0

report_matches() {
  local category="$1"
  local pattern="$2"
  local path output

  for path in "${files[@]}"; do
    grep -Iq . "$path" || continue
    output="$(LC_ALL=C grep -nE "$pattern" "$path" 2>/dev/null || true)"
    [[ -n "$output" ]] || continue
    findings=1
    while IFS= read -r match; do
      printf 'finding: %s: %s:%s\n' "$category" "$path" "${match%%:*}"
    done <<< "$output"
  done
}

printf 'audit: checking %d changed/untracked files\n' "${#files[@]}"

for path in "${files[@]}"; do
  grep -Iq . "$path" || continue
  if LC_ALL=C grep -q $'\r$' "$path"; then
    printf 'finding: CRLF line endings: %s\n' "$path"
    findings=1
  fi
done

report_matches 'merge-conflict marker' '^(<<<<<<<|=======|>>>>>>>)($| )'
report_matches 'private-key material' '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----'
report_matches 'AWS access key' '(AKIA|ASIA)[A-Z0-9]{16}'
report_matches 'GitHub token' 'gh[pousr]_[A-Za-z0-9]{20,}'
report_matches 'OpenAI-style secret key' 'sk-[A-Za-z0-9_-]{20,}'
report_matches 'Google API key' 'AIza[0-9A-Za-z_-]{30,}'
report_matches 'suspicious credential assignment' '(api[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|password)[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}'
report_matches 'personal home path' "/home/${USER}(/|$)"
identity_file="$repo/.agents/skills/commit-dotfiles/identity.local"
if [[ -f "$identity_file" ]]; then
  personal_name_pattern=''
  source "$identity_file"
  [[ -n "$personal_name_pattern" ]] && report_matches 'personal name' "(${personal_name_pattern})"
fi
report_matches 'personal email address' '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|protonmail)\.[A-Za-z]{2,}'

if command -v gitleaks >/dev/null 2>&1; then
  printf 'audit: running gitleaks on the working tree\n'
  if ! gitleaks dir --no-banner --redact --no-color "$repo"; then
    printf 'finding: gitleaks reported one or more candidates (%s values)\n' "$REDACT"
    findings=1
  fi
else
  printf 'audit: gitleaks unavailable; built-in signature scan used\n'
fi

if ! git diff --check HEAD --; then
  findings=1
fi

if (( findings )); then
  printf 'audit: findings require review before commit\n' >&2
  exit 1
fi

printf 'audit: clean\n'
