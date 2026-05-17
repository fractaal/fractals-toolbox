# tquit — leave the current auto tmux session without dropping the terminal/SSH.
# Switch this tmux client to an idle session (or create one), then kill the
# session we came from.
# Usage: tquit
#        tq
#        texit

tquit() { "$HOME/.fractals-toolbox/common/bin/tquit" "$@"; }

alias tq=tquit
alias texit=tquit
