# Auto-attach a new interactive terminal to an idle disposable tmux session,
# or spawn a fresh one if none are available.
# Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing.
if status is-interactive; and not set -q TMUX; and type -q tmux
    if test -x "$HOME/.fractals-toolbox/common/bin/tmux-idle-session"
        set -l idle_session ($HOME/.fractals-toolbox/common/bin/tmux-idle-session find 2>/dev/null)
        if test -n "$idle_session"
            exec tmux attach -t "$idle_session"
        end
    end

    exec tmux new -s "term-$fish_pid"
end
