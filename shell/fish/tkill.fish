# tkill — kill tmux sessions by direct fuzzy match, or repeatedly via fzf picker.
# Usage: tkill [--force] [pattern]
#        tk    [--force] [pattern]
#        tkill-tui [--force] [initial-query]
#        tkt       [--force] [initial-query]
#
# No args opens a picker: Enter kills the highlighted session, reloads the
# same list, and stays open until Escape. Current session is hidden unless
# --force is passed.

function tkill --description 'Kill tmux sessions by direct match, or picker with no args'
    "$HOME/.fractals-toolbox/common/bin/tkill" $argv
end

function tkill-tui --description 'Pick tmux sessions in fzf and kill them with Enter'
    "$HOME/.fractals-toolbox/common/bin/tkill-tui" $argv
end

alias tk=tkill
alias tkt=tkill-tui
