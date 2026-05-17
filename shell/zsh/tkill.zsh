# tkill — kill tmux sessions by direct fuzzy match, or repeatedly via fzf picker.
# Usage: tkill [--force] [pattern]
#        tk    [--force] [pattern]
#        tkill-tui [--force] [initial-query]
#        tkt       [--force] [initial-query]
#
# No args opens a picker: Enter kills the highlighted session, reloads the
# same list, and stays open until Escape. Current session is hidden unless
# --force is passed.

tkill() { "$HOME/.fractals-toolbox/common/bin/tkill" "$@"; }
tkill-tui() { "$HOME/.fractals-toolbox/common/bin/tkill-tui" "$@"; }

alias tk=tkill
alias tkt='tkill-tui'
