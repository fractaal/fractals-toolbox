# tjoin — join tmux sessions by direct fuzzy match, or via fzf picker with no args.
# Usage: tjoin [pattern]
#        tj    [pattern]
#        tjoin-tui [initial-query]
#        tjt       [initial-query]

tjoin() { "$HOME/.fractals-toolbox/common/bin/tjoin" "$@"; }
tjoin-tui() { "$HOME/.fractals-toolbox/common/bin/tjoin-tui" "$@"; }

alias tj=tjoin
alias tjt='tjoin-tui'
