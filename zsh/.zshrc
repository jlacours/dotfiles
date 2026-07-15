# =========================
# Juju's .zshrc (working for fzf 0.68)
# =========================

# --- Environment Variables ---
# Attach to the always-on Emacs daemon (systemd --user emacs.service).
# -t: terminal frame; -a: fallback if no server running.
export EDITOR="emacsclient -t -a 'emacs -nw'"
export VISUAL="emacsclient -c -a 'emacs'"
export SUDO_EDITOR="$EDITOR"
[[ -S "/run/user/$UID/gcr/ssh" ]] && export SSH_AUTH_SOCK="/run/user/$UID/gcr/ssh"

# --- History ---
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
setopt EXTENDED_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# --- PATH ---
# Prepend to PATH without duplicates (safe against re-sourcing)
path_prepend() {
  local dir="$1"
  path=("${(@)path:#$dir}")
  path=("$dir" $path)
  export PATH
}

export PNPM_HOME="$HOME/.local/share/pnpm"

path_prepend "$HOME/.cargo/bin"
path_prepend "$HOME/.npm-global/bin"
path_prepend "$PNPM_HOME"
path_prepend "$HOME/repos/llama.cpp/build/bin"
path_prepend "$HOME/.local/bin"

# --- Vanilla Zsh Plugins ---
# Plugins live outside Oh My Zsh and are loaded directly with standard zsh.
export ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "$ZSH_CACHE_DIR"

# Make custom completions and plugin completions visible before compinit.
fpath=(
  "$HOME/.zfunc"
  "$ZSH_PLUGIN_DIR/wallust"
  "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
  "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
  $fpath
)

autoload -Uz compinit colors
zmodload zsh/complist
colors
compinit -d "$ZSH_CACHE_DIR/zcompdump"

source_if_readable() { [[ -r "$1" ]] && source "$1"; }

# Helper expected by the vendored git aliases plugin.
git_current_branch() {
  command git symbolic-ref --quiet --short HEAD 2>/dev/null \
    || command git rev-parse --short HEAD 2>/dev/null
}

source_if_readable "$ZSH_PLUGIN_DIR/git/git.plugin.zsh"
source_if_readable "$ZSH_PLUGIN_DIR/colorize/colorize.plugin.zsh"
source_if_readable "$ZSH_PLUGIN_DIR/colored-man-pages/colored-man-pages.plugin.zsh"
source_if_readable "$ZSH_PLUGIN_DIR/man/man.plugin.zsh"
source_if_readable "$ZSH_PLUGIN_DIR/wallust/wallust.plugin.zsh"
source_if_readable "$ZSH_PLUGIN_DIR/fzf-tab/fzf-tab.plugin.zsh"

# command-not-found: source the platform handler when present.
for command_not_found_file in \
  /usr/share/doc/pkgfile/command-not-found.zsh \
  /usr/share/zsh/plugins/xbps-command-not-found/xbps-command-not-found.zsh; do
  if [[ -r "$command_not_found_file" ]]; then
    source "$command_not_found_file"
    break
  fi
done
unset command_not_found_file

# Debian/Ubuntu-style command-not-found helper, if installed.
if [[ -x /usr/lib/command-not-found || -x /usr/share/command-not-found/command-not-found ]]; then
  command_not_found_handler() {
    if [[ -x /usr/lib/command-not-found ]]; then
      /usr/lib/command-not-found -- "$1"
    else
      /usr/share/command-not-found/command-not-found -- "$1"
    fi
  }
fi

# thefuck integration, without Oh My Zsh.
if (( $+commands[thefuck] )); then
  [[ -r "$ZSH_CACHE_DIR/thefuck" ]] || thefuck --alias >| "$ZSH_CACHE_DIR/thefuck"
  source "$ZSH_CACHE_DIR/thefuck"

  fuck-command-line() {
    local -a last_command
    local fixed_command
    last_command=("${(z)$(fc -ln -1)}")
    (( $#last_command )) || return
    fixed_command="$(THEFUCK_REQUIRE_CONFIRMATION=0 thefuck "${last_command[@]}" 2>/dev/null)"
    [[ -z "$fixed_command" ]] && echo -n -e "\a" && return
    BUFFER="$fixed_command"
    zle end-of-line
  }
  zle -N fuck-command-line
  bindkey -M emacs '\e\e' fuck-command-line
fi

if [[ -z $ZSH_DISABLE_AUTOSUGGESTIONS ]]; then
  source_if_readable "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if (( $+widgets[autosuggest-accept] )); then
  bindkey '^F' autosuggest-accept
fi

# --- Aliases ---
alias zshconfig="$EDITOR ~/.zshrc"
alias ls="eza -a --color=always --icons=always --group-directories-first"
alias ll="eza -a -l --color=always --icons=always --group-directories-first"
alias lz="eza -a --color=always --icons=always --group-directories-first"
alias clr="clear"
alias nb="newsboat -x open"
alias cdnt="cd ~/Notes"
alias newmatrix='neo-matrix -C ~/.config/neo/colors -m "Fuck Off"'
alias sysinfo='macchina'
alias cdx='codex-tmux'
alias codex-ssh='codex-tmux'

# Run Claude Code through the local CLIProxyAPI subscription gateway.
claudex() {
  local token_file="$HOME/.cli-proxy-api/client-token"

  if [[ ! -r "$token_file" ]]; then
    print -u2 "claudex: missing proxy token at $token_file"
    return 1
  fi

  ANTHROPIC_BASE_URL="http://127.0.0.1:8317" \
  ANTHROPIC_AUTH_TOKEN="$(<"$token_file")" \
  ANTHROPIC_API_KEY="" \
  ANTHROPIC_MODEL="gpt-5.6-sol" \
  ANTHROPIC_SMALL_FAST_MODEL="gpt-5.6-luna" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-5.6-sol" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="gpt-5.6-terra" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="gpt-5.6-luna" \
  CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1 \
  API_TIMEOUT_MS=3000000 \
    command claude "$@"
}

# NoPayStation — defaults to /mnt/Extra/ for downloads
unalias npsget 2>/dev/null
npsget() {
  if [[ "$*" != *-o* ]]; then
    command npsget -o /mnt/Extra "$@"
  else
    command npsget "$@"
  fi
}

mkcd() {
  if (( $# != 1 )); then
    print -u2 "usage: mkcd <directory>"
    return 2
  fi

  mkdir -p -- "$1" && cd -- "$1"
}

# --- Line Editing ---
# Prefix-aware history search on Up/Down arrows.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# Edit the current command line in $EDITOR (CTRL-x CTRL-e). Save & quit to run it.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Ctrl+Arrow word navigation.
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[5C' forward-word
bindkey '^[[5D' backward-word

# --- Zsh Options ---
# Include dotfiles in globs
setopt globdots
setopt autocd
setopt numericglobsort
setopt auto_list
setopt auto_menu
cdpath=(
  $HOME
  $HOME/Projects
  $HOME/repos
)

# Prevent accidental terminal freezes from software flow control.
[[ -t 0 ]] && stty -ixon 2>/dev/null

# --- Node Version Manager (nvm) ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- Custom Prompt ---
setopt PROMPT_SUBST
autoload -Uz vcs_info

# Git status indicators:
#   * = unstaged changes (modified files not yet added)
#   + = staged changes (files added, ready to commit)
#  ** = untracked files (new files git doesn't know about)
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats '%b%u%c%m'
zstyle ':vcs_info:git:*' actionformats '%b%u%c%m (%a)'

# Reset extended keyboard modes that TUIs can leave enabled after a crash/kill.
# Run unconditionally: terminals that don't implement the kitty keyboard
# protocol ignore these sequences, and foot (the default terminal) supports it.
reset_terminal_input_modes() {
  printf '\e[<u\e[<u\e[<u\e[>4;0m'
}

# Hook to detect untracked files and show ** indicator
+vi-git-untracked() {
  if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == 'true' ]]; then
    if [[ -n $(git ls-files --others --exclude-standard 2>/dev/null) ]]; then
      hook_com[misc]='**'
    fi
  fi
}

zstyle ':vcs_info:git*+set-message:*' hooks git-untracked

precmd() {
  local exit_code=$?
  reset_terminal_input_modes
  vcs_info

  # Exit code display (only shown when non-zero)
  if (( exit_code != 0 )); then
    EXIT_STATUS=" %F{red}${exit_code}%f"
  else
    EXIT_STATUS=""
  fi

  # Git info
  local italic_on=$'\x1b[3m'
  local italic_off=$'\x1b[23m'
  if [[ -n ${vcs_info_msg_0_} ]]; then
    GIT_INFO=" %F{green}%{${italic_on}%}${vcs_info_msg_0_}%{${italic_off}%}%f"
  else
    GIT_INFO=""
  fi

  # Python venv indicator
  if [[ -n $VIRTUAL_ENV ]]; then
    VENV_INFO="%F{yellow}($(basename -- "$VIRTUAL_ENV"))%f "
  else
    VENV_INFO=""
  fi

  # LLM auto-approve indicator
  if [[ -n $LLM_AUTO_APPROVE ]]; then
    LLM_INFO="%F{red}[llm-auto-approve]%f "
  else
    LLM_INFO=""
  fi

  # Sudo ticket indicator
  if [[ -n $SUDO_READY ]]; then
    SUDO_INFO="%F{yellow}[sudo-ready]%f "
  else
    SUDO_INFO=""
  fi
}

# Transient prompt - simplify previous prompt after command execution
function zle-line-finish {
  PROMPT='%F{%(?.green.red)}❯%f '
  # reset cursor shape + color when leaving the line
  printf '\e[0 q\e]112\a'
  zle reset-prompt
  set-full-prompt
}
zle -N zle-line-finish

# zsh-syntax-highlighting currently freezes this setup when the buffer reaches
# "pi". Keep it opt-in until the plugin is replaced or updated.
if [[ -n $ZSH_ENABLE_SYNTAX_HIGHLIGHTING ]]; then
  source_if_readable "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

function set-full-prompt {
  PROMPT=$'
%F{cyan}%n@%m%f
%{\x1b[3m%}%~%{\x1b[23m%}${EXIT_STATUS}${GIT_INFO}
${LLM_INFO}${SUDO_INFO}${VENV_INFO}%B%F{green}❯%f%b '
}
set-full-prompt

# --- Completion tweaks ---
# Show descriptions next to flags/matches (fish-style). 'verbose' is zsh's
# default but stated here so it survives future style experiments;
# auto-description covers options whose spec has an argument but no text.
zstyle ':completion:*' verbose yes
zstyle ':completion:*' auto-description 'specify: %d'

# Remove ../ and ./ from completion results
zstyle ':completion:*' special-dirs false
zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' list-dirs-first true
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS} 'ma=48;5;238;38;5;15;1'
# Native tmux completion documents every command; omit duplicate short aliases.
zstyle ':completion:*:*:tmux:*:subcommands' mode 'commands'

# Dart CLI Completion (if installed)
[[ -f ~/.config/.dart-cli-completion/zsh-config.zsh ]] && . ~/.config/.dart-cli-completion/zsh-config.zsh || true

# Keep Zsh's mature native completers, then use Carapace only to fill gaps.
# Commands unsupported by both systems retain Zsh's fast built-in fallback.
if command -v carapace >/dev/null 2>&1; then
  typeset -A native_completers
  native_completers=("${(@kv)_comps}")

  source <(carapace _carapace zsh)

  for completion_command completion_function in "${(@kv)native_completers}"; do
    _comps[$completion_command]=$completion_function
  done
  unset native_completers completion_command completion_function
fi

source_if_readable "$HOME/.zfunc/_opencode"
source_if_readable "$HOME/.zfunc/_claude"

# --- FZF Setup ---
unset FZF_DEFAULT_OPTS

# Base FZF settings: layout, border, preview, keybindings
export FZF_DEFAULT_OPTS="
--layout=reverse
--border=sharp
--info=inline
--preview-window=right:60%
--bind=ctrl-u:preview-half-page-up
--bind=ctrl-d:preview-half-page-down
--bind=ctrl-p:toggle-preview
"

# Optional: Wallust dynamic colors for fzf
# Only applied if using newer fzf versions or for CLI calls
if [[ -f ~/.cache/wallust/colors.sh ]]; then
    source ~/.cache/wallust/colors.sh
    # Add color options only for commands that support hex values
    # Note: fzf 0.68 requires separate --color flags (no comma-separated values)
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
    --color=bg:$background
    --color=fg:$foreground
    --color=hl:$color1
    --color=hl+:$color5
    --color=pointer:$color6
    --color=marker:$color3
    "
fi

# Source fzf keybindings and fuzzy completion.
# fzf 0.72 snapshots the readonly zle option and errors when restoring it.
source_fzf_zsh() {
  local fzf_script
  fzf_script="$(fzf --zsh 2>/dev/null)" || return 1

  if [[ $fzf_script == *'__fzf_key_bindings_options="options='* ||
        $fzf_script == *'__fzf_completion_options="options='* ]]; then
    print -r -- "$fzf_script" | sed -E \
    -e '/__fzf_key_bindings_options="options=/a\  __fzf_key_bindings_options=${__fzf_key_bindings_options/ zle on/}' \
    -e '/__fzf_key_bindings_options="options=/a\  __fzf_key_bindings_options=${__fzf_key_bindings_options/ zle off/}' \
    -e '/__fzf_completion_options="options=/a\  __fzf_completion_options=${__fzf_completion_options/ zle on/}' \
    -e '/__fzf_completion_options="options=/a\  __fzf_completion_options=${__fzf_completion_options/ zle off/}'
  else
    print -r -- "$fzf_script"
  fi
}
command -v fzf >/dev/null 2>&1 && source <(source_fzf_zsh)

# FZF function for editing files
fe() { fzf -m --preview='bat --color=always {}' --bind 'enter:become(nvim {+})'; }

# Extract common archives using the tools installed on this machine.
extract() {
  if (( $# != 1 )); then
    print -u2 "usage: extract <archive>"
    return 2
  fi

  local archive="$1"
  if [[ ! -f $archive ]]; then
    print -u2 "extract: not a file: $archive"
    return 1
  fi

  case "${archive:l}" in
    (*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz|*.tbz2|*.tar.xz|*.txz|*.tar.lzma|*.tlz|*.tar.zst|*.tzst)
      tar -xf "$archive"
      ;;
    (*.zip)
      unzip "$archive"
      ;;
    (*.7z|*.rar)
      7z x "$archive"
      ;;
    (*.gz)
      gunzip -- "$archive"
      ;;
    (*.bz2)
      bunzip2 -- "$archive"
      ;;
    (*.xz)
      unxz -- "$archive"
      ;;
    (*.lzma)
      unlzma -- "$archive"
      ;;
    (*.zst)
      unzstd -- "$archive"
      ;;
    (*.lz4)
      unlz4 -- "$archive"
      ;;
    (*)
      print -u2 "extract: unsupported archive type: $archive"
      return 1
      ;;
  esac
}

ex7z() {
  extract "$1"
}

alias claudev='claude --verbose'

# System update: packages + Neovim plugins
update() {
  echo "==> Updating packages..."
  yay -Syu

  echo "==> Updating Neovim plugins..."
  time nvim --headless "+Lazy! update" +qa

  echo "==> Done."
}

# Toggle LLM auto-approve (skips tool confirmation prompts)
function llm-approve() {
  if [[ -z "$LLM_AUTO_APPROVE" ]]; then
    export LLM_AUTO_APPROVE=1
    echo "LLM auto-approve enabled"
  else
    unset LLM_AUTO_APPROVE
    echo "LLM auto-approve disabled"
  fi
}

# Toggle passwordless pacman (sudoers drop-in) so non-interactive agent
# subprocesses without a TTY can run `yay` / `sudo pacman`. Run these from your
# interactive shell — you enter your password once to flip the drop-in on/off.
# (Plain `sudo -v` doesn't work for this: the cached timestamp is TTY/session
# scoped and does NOT transfer to agent-harness subprocesses.)
SUDOERS_PACMAN=/etc/sudoers.d/pacman-nopasswd

function sudo-on() {
  local tmp
  tmp=$(mktemp) || return 1
  echo 'juju ALL=(ALL) NOPASSWD: /usr/bin/pacman' > "$tmp"
  # Validate BEFORE installing: a malformed sudoers file can lock out sudo.
  if ! sudo visudo -cf "$tmp" >/dev/null; then
    rm -f "$tmp"
    echo "sudo-on: sudoers syntax invalid — aborted, sudo unchanged" >&2
    return 1
  fi
  if ! sudo install -m 440 -o root -g root "$tmp" "$SUDOERS_PACMAN"; then
    rm -f "$tmp"
    echo "sudo-on: failed to install sudoers drop-in (auth cancelled?)" >&2
    return 1
  fi
  rm -f "$tmp"
  export SUDO_READY=1
  echo "passwordless pacman ON — agents can run yay / sudo pacman"
}

function sudo-off() {
  # rm -f is idempotent: a non-root user can't stat /etc/sudoers.d/, so an
  # existence pre-check would always report "absent". Just remove and rely on
  # the exit code.
  if ! sudo rm -f "$SUDOERS_PACMAN"; then
    echo "sudo-off: failed to remove sudoers drop-in (auth cancelled?)" >&2
    return 1
  fi
  unset SUDO_READY
  echo "passwordless pacman OFF — agents will prompt for sudo again"
}

# Hermes Agent — ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"
