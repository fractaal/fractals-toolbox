# tquit — leave the current auto tmux session without dropping the terminal/SSH.
# Switch this tmux client to an idle session (or create one), then kill the
# session we came from.
# Usage: tquit
#        tq
#        texit

if ! whence -w _fractals_tmux_current_session >/dev/null 2>&1 \
  && [[ -r "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh" ]]; then
  source "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh"
fi

tquit() {
  local current target
  current="$(_fractals_tmux_current_session)"
  if [[ -z "$current" ]]; then
    echo "tquit: not inside a tmux client." >&2
    return 1
  fi

  target="$(_fractals_tmux_idle_session ensure --exclude-current --cwd "$PWD")" || return $?
  if [[ -z "$target" ]]; then
    echo "tquit: failed to find or create an idle target session." >&2
    return 1
  fi
  if [[ "$target" == "$current" ]]; then
    echo "tquit: idle target resolved to current session; refusing." >&2
    return 1
  fi

  echo "Switching to $target; killing $current"
  tmux switch-client -t "$target" || return $?
  tmux kill-session -t "$current"
}

alias tq=tquit
alias texit=tquit
