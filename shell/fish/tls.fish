function tls --description 'List tmux sessions with pane-title summary'
    tmux list-sessions -F '#{session_name}  #{?session_attached,●,○}  #{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
        | sed 's/ | $//'
end
