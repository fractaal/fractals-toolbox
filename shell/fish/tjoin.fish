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
    # Escape regex meta so the user's pattern is treated as a literal substring
    # (matches zsh's [[ "$haystack" == *"$pattern"* ]] semantics).
    set -l escaped (string escape --style=regex -- $pattern)
    set -l current_session
    if set -q TMUX
        set current_session (tmux display-message -p '#{client_session}' 2>/dev/null)
    end
    set -l session_matches
    set -l title_matches
    set -l matches

    set -l lines (tmux list-sessions -F '#{session_name}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }')
    for line in $lines
        set -l parts (string split -m 1 \t -- $line)
        set -l name $parts[1]
        set -l titles $parts[2]
        set -l lower_name (string lower -- $name)
        set -l lower_titles (string lower -- $titles)

        if string match -qr -- ".*$escaped.*" $lower_name
            set -a session_matches $line
        else if test "$name" != "$current_session"; and string match -qr -- ".*$escaped.*" $lower_titles
            set -a title_matches $line
        end
    end

    # Prefer stable session ids/names over volatile pane titles. Also do not let
    # the current pane title match the just-run command, e.g. `tjoin 758`.
    if test (count $session_matches) -gt 0
        set matches $session_matches
    else
        set matches $title_matches
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
