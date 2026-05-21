# Bail out of tmux back to a plain shell in the same terminal window.
# Works because we no longer `exec` tmux below — the parent shell is still alive
# and resumes when tmux detaches.
alias bail='tmux detach-client'

# Auto-spawn a fresh tmux session per interactive terminal window.
# Skips inside an existing tmux session, in non-interactive shells, when tmux is
# missing, or when NO_TMUX=1 is set (use for `NO_TMUX=1 ssh remote` to launch
# without local-tmux wrapping, so the remote's tmux is the only one).
if [[ -z "$TMUX" ]] && [[ -z "$NO_TMUX" ]] && [[ $- == *i* ]] && [[ -n "$PS1" ]] && command -v tmux >/dev/null 2>&1; then
  tmux new -s "term-$$"
  # When tmux exits/detaches, fall through to the interactive shell.
fi
