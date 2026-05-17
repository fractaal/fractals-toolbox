# tkill — case-insensitive substring match a tmux session by name or pane title,
# then kill the unique match.
# Usage: tkill [--force] [pattern]
#        tk    [--force] [pattern]
#        tkill-tui [--force] [initial-query]
#        tkt       [--force] [initial-query]

if not functions -q __fractals_tmux_session_rows
    if test -r "$HOME/.fractals-toolbox/shell/fish/tmux-sessions.fish"
        source "$HOME/.fractals-toolbox/shell/fish/tmux-sessions.fish"
    end
end

function __fractals_tkill_kill_session -a name titles
    echo "Killing $name \"$titles\""
    tmux kill-session -t $name
end

function tkill --description 'Pick or fuzzy-match a tmux session by name/pane title and kill it'
    set -l force 0
    set -l args $argv
    if test (count $args) -gt 0
        switch $args[1]
            case -f --force
                set force 1
                set args $args[2..-1]
        end
    end

    if test (count $args) -eq 0
        if test $force -eq 1
            tkill-tui --force
        else
            tkill-tui
        end
        return $status
    end

    set -l query (string join ' ' -- $args)
    set -l pattern (string lower -- $query)
    # Escape regex meta so the user's pattern is treated as a literal substring
    # (matches zsh's [[ "$haystack" == *"$pattern"* ]] semantics).
    set -l escaped (string escape --style=regex -- $pattern)
    set -l current_session (__fractals_tmux_current_session)
    set -l session_matches
    set -l title_matches
    set -l matches

    for line in (__fractals_tmux_session_rows)
        set -l parts (string split -m 2 \t -- $line)
        set -l name $parts[1]
        set -l titles $parts[3]
        set -l lower_name (string lower -- $name)
        set -l lower_titles (string lower -- $titles)

        if string match -qr -- ".*$escaped.*" $lower_name
            set -a session_matches "$name	$titles"
        else if test "$name" != "$current_session"; and string match -qr -- ".*$escaped.*" $lower_titles
            set -a title_matches "$name	$titles"
        end
    end

    # Prefer stable session ids/names over volatile pane titles. Also do not let
    # the current pane title match the just-run command, e.g. `tkill 758`.
    if test (count $session_matches) -gt 0
        set matches $session_matches
    else
        set matches $title_matches
    end

    set -l n (count $matches)
    if test $n -eq 0
        echo "tkill: no session matches '$query'" >&2
        return 1
    else if test $n -gt 1
        echo "tkill: '$query' is ambiguous, matches $n sessions:" >&2
        for m in $matches
            set -l parts (string split -m 1 \t -- $m)
            set -l ti (string trim -r -c ' |' -- $parts[2])
            echo "  $parts[1]  $ti" >&2
        end
        return 1
    end

    set -l parts (string split -m 1 \t -- $matches[1])
    set -l name $parts[1]
    set -l title (string trim -r -c ' |' -- $parts[2])

    if test -n "$current_session"; and test "$name" = "$current_session"; and test $force -ne 1
        echo "tkill: refusing to kill current session '$name' (use --force to override)." >&2
        return 1
    end

    __fractals_tkill_kill_session $name $title
end

function tkill-tui --description 'Pick a tmux session in fzf and kill it'
    set -l force 0
    set -l args $argv
    if test (count $args) -gt 0
        switch $args[1]
            case -f --force
                set force 1
                set args $args[2..-1]
        end
    end

    set -l row (__fractals_tmux_pick_session tkill 'select a tmux session to kill' $args)
    or return $status

    set -l name (__fractals_tmux_row_name $row)
    set -l title (__fractals_tmux_row_titles $row)
    set -l current_session (__fractals_tmux_current_session)

    if test -n "$current_session"; and test "$name" = "$current_session"; and test $force -ne 1
        echo "tkill-tui: refusing to kill current session '$name' (use --force to override)." >&2
        return 1
    end

    read -l -P "Kill tmux session '$name'? [y/N] " answer
    switch (string lower -- $answer)
        case y yes
        case '*'
            echo Cancelled
            return 1
    end

    __fractals_tkill_kill_session $name $title
end

alias tk=tkill
alias tkt=tkill-tui
