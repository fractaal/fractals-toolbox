# Auto-spawn a fresh tmux session per interactive terminal window.
# Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing.
if status is-interactive; and not set -q TMUX; and type -q tmux
    exec tmux new -s "term-$fish_pid"
end
