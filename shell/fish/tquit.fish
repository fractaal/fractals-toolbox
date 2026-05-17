# tquit — leave the current auto tmux session without dropping the terminal/SSH.
# Switch this tmux client to an idle session (or create one), then kill the
# session we came from.
# Usage: tquit
#        tq
#        texit

function tquit --description 'Switch to an idle tmux session, then kill the current one'
    "$HOME/.fractals-toolbox/common/bin/tquit" $argv
end

alias tq=tquit
alias texit=tquit
