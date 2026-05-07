# Auto-spawn a fresh tmux session per interactive terminal window.
# Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing.
if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && [[ -n "$PS1" ]] && command -v tmux >/dev/null 2>&1; then
  exec tmux new -s "term-$$"
fi
