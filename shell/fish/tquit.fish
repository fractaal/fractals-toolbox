# tquit — leave the current auto tmux session without dropping the terminal/SSH.
# Switch this tmux client to an idle session (or create one), then kill the
# session we came from.
# Usage: tquit
#        tq
#        texit

if not functions -q __fractals_tmux_current_session
    if test -r "$HOME/.fractals-toolbox/shell/fish/tmux-sessions.fish"
        source "$HOME/.fractals-toolbox/shell/fish/tmux-sessions.fish"
    end
end

function tquit --description 'Switch to an idle tmux session, then kill the current one'
    set -l current (__fractals_tmux_current_session)
    if test -z "$current"
        echo "tquit: not inside a tmux client." >&2
        return 1
    end

    set -l target (__fractals_tmux_idle_session ensure --exclude-current --cwd "$PWD")
    or return $status
    if test -z "$target"
        echo "tquit: failed to find or create an idle target session." >&2
        return 1
    end
    if test "$target" = "$current"
        echo "tquit: idle target resolved to current session; refusing." >&2
        return 1
    end

    echo "Switching to $target; killing $current"
    tmux switch-client -t $target
    or return $status
    tmux kill-session -t $current
end

alias tq=tquit
alias texit=tquit
