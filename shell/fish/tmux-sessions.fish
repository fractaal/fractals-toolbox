# Shared tmux session helpers for tls/tjoin/tkill family commands.

function __fractals_tmux_session_rows
    tmux list-sessions -F '#{session_name}	#{?session_attached,●,○}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
        | sed 's/ | $//'
end

function __fractals_tmux_current_session
    if set -q TMUX
        tmux display-message -p '#{client_session}' 2>/dev/null
    end
end

function __fractals_tmux_row_name -a row
    set -l parts (string split -m 2 \t -- $row)
    printf '%s' $parts[1]
end

function __fractals_tmux_row_titles -a row
    set -l parts (string split -m 2 \t -- $row)
    if test (count $parts) -ge 3
        string trim -r -c ' |' -- $parts[3]
    end
end

function __fractals_tmux_pick_session
    set -l prompt $argv[1]
    set -l header $argv[2]
    set -l query (string join ' ' -- $argv[3..-1])

    if not command -q fzf
        echo "$prompt: fzf is required for the TUI picker." >&2
        return 127
    end

    set -l rows (__fractals_tmux_session_rows 2>/dev/null)
    if test (count $rows) -eq 0
        echo "$prompt: no tmux sessions found." >&2
        return 1
    end

    set -l fzf_args \
        --delimiter \t \
        --with-nth 1,2,3 \
        --prompt "$prompt> " \
        --height 80% \
        --layout reverse \
        --border \
        --header "$header"

    if test -n "$query"
        set -a fzf_args --query "$query"
    end

    set -l selected (printf '%s\n' $rows | fzf $fzf_args)
    if test -z "$selected"
        return 130
    end

    printf '%s\n' $selected
end
