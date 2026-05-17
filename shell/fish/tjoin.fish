# tjoin — join tmux sessions by direct fuzzy match, or via fzf picker with no args.
# Usage: tjoin [pattern]
#        tj    [pattern]
#        tjoin-tui [initial-query]
#        tjt       [initial-query]

function tjoin --description 'Join tmux sessions by direct match, or picker with no args'
    "$HOME/.fractals-toolbox/common/bin/tjoin" $argv
end

function tjoin-tui --description 'Pick a tmux session in fzf and switch to it'
    "$HOME/.fractals-toolbox/common/bin/tjoin-tui" $argv
end

alias tj=tjoin
alias tjt=tjoin-tui
