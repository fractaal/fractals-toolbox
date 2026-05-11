# tjoin — case-insensitive substring match a tmux session by name or pane title,
# then switch to it (switch-client inside tmux, attach from outside).
# Usage: tjoin <pattern>
#        tj    <pattern>
function tjoin --description 'Fuzzy-match a tmux session by name/pane title and switch to it'
    if test (count $argv) -eq 0
        echo "Usage: tjoin <pattern>" >&2
        return 1
    end

    set -l pattern (string lower -- $argv[1])
    set -l matches

    set -l lines (tmux list-sessions -F '#{session_name}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }')
    for line in $lines
        set -l haystack (string lower -- $line)
        if string match -q -- "*$pattern*" $haystack
            set -a matches $line
        end
    end

    set -l n (count $matches)
    if test $n -eq 0
        echo "tjoin: no session matches '$argv[1]'" >&2
        return 1
    else if test $n -gt 1
        echo "tjoin: '$argv[1]' is ambiguous, matches $n sessions:" >&2
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

    echo "Joining $name \"$title\""

    if set -q TMUX
        tmux switch-client -t $name
    else
        tmux attach -t $name
    end
end

alias tj=tjoin
