# shared-env — broadcast env vars to all active zsh sessions
#
# Source this file from ~/.zshrc (home-manager does this automatically).
# It installs a precmd hook that re-sources a shared file before every
# prompt, but only when the file's mtime changes — zero overhead on
# prompts where nothing changed.
#
# Usage:
#   shared-env NAME "value"    # set — all shells pick it up on next prompt
#   shared-env-rm NAME         # remove from the shared store
#
# The shared file lives at $SHARED_ENV_FILE (default:
# ~/.config/shell-env/env).  It is a plain shell file with `export`
# lines, rewritten atomically on every update.
#
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2296,SC1090,SC1103

autoload -Uz add-zsh-hook
typeset -g _zsh_shared_env_mtime=0
: "${SHARED_ENV_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/shell-env/env}"

# Set a variable in the shared store.
# Rewrites the whole file atomically so concurrent writes are safe.
shared-env() {
  local name=$1 value=$2
  local file=$SHARED_ENV_FILE
  mkdir -p "${file:h}"
  {
    # Keep existing entries except the one we're updating.
    [[ -f "$file" ]] && grep -v "^export $name=" "$file" 2>/dev/null || true
    # Write the new entry with zsh-safe quoting.
    printf 'export %s=%s\n' "$name" "${(q)value}"
  } > "$file.tmp" && mv "$file.tmp" "$file"
}

# Remove a variable from the shared store.
shared-env-rm() {
  local name=$1 file=$SHARED_ENV_FILE
  [[ -f "$file" ]] || return 0
  grep -v "^export $name=" "$file" > "$file.tmp" 2>/dev/null || true
  mv "$file.tmp" "$file"
}

# precmd hook: source the shared file only when it actually changed.
_load_shared_env() {
  local file=$SHARED_ENV_FILE
  [[ -f "$file" ]] || return

  local mtime
  if zmodload zsh/stat 2>/dev/null; then
    zstat -A mtime +mtime "$file" 2>/dev/null || return
  elif mtime=$(stat -c %Y "$file" 2>/dev/null); then
    : # GNU stat (Linux)
  else
    mtime=$(stat -f %m "$file" 2>/dev/null) || return  # BSD stat (macOS)
  fi

  if [[ $mtime != "$_zsh_shared_env_mtime" ]]; then
    source "$file"
    _zsh_shared_env_mtime=$mtime
  fi
}
add-zsh-hook precmd _load_shared_env
