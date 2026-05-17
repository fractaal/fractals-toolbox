# Shared tmux session helpers for tls/tjoin/tkill/tquit family commands.

function __fractals_tmux_session_rows
    set -l helper "$HOME/.fractals-toolbox/common/bin/tmux-session-rows"
    if test -x "$helper"
        "$helper" $argv
    else
        tmux list-sessions -F '#{session_name}	#{?session_attached,●,○}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
            | sed 's/ | $//'
    end
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

function __fractals_tmux_kill_picker
    set -l force 0
    set -l args $argv
    if test (count $args) -gt 0; and test "$args[1]" = --force
        set force 1
        set args $args[2..-1]
    end

    if not command -q fzf
        echo "tkill: fzf is required for the TUI picker." >&2
        return 127
    end

    set -l helper "$HOME/.fractals-toolbox/common/bin/tmux-session-rows"
    if not test -x "$helper"
        echo "tkill: missing $helper" >&2
        return 1
    end

    set -l row_args
    if test $force -ne 1
        set row_args --exclude-current
    end

    set -l rows ($helper $row_args 2>/dev/null)
    if test (count $rows) -eq 0
        if test $force -eq 1
            echo "tkill: no tmux sessions found." >&2
        else
            echo "tkill: no killable sessions found (current session is hidden; use --force to include it)." >&2
        end
        return 1
    end

    set -l query (string join ' ' -- $args)
    set -l reload_cmd (string escape -- $helper $row_args)
    set reload_cmd (string join ' ' -- $reload_cmd)
    set -l header 'enter kill highlighted • ctrl-r refresh • esc done'
    if test $force -ne 1
        set header "$header • current session hidden (--force includes it)"
    end

    set -l fzf_args \
        --delimiter \t \
        --with-nth 1,2,3 \
        --prompt 'tkill> ' \
        --height 80% \
        --layout reverse \
        --border \
        --header "$header" \
        --bind "enter:execute-silent(tmux kill-session -t {1})+reload($reload_cmd)" \
        --bind "ctrl-r:reload($reload_cmd)"

    if test -n "$query"
        set -a fzf_args --query "$query"
    end

    printf '%s\n' $rows | fzf $fzf_args >/dev/null
end

function __fractals_tmux_idle_session
    set -l helper "$HOME/.fractals-toolbox/common/bin/tmux-idle-session"
    if not test -x "$helper"
        return 1
    end
    "$helper" $argv
end
