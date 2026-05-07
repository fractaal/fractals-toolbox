# tls — list tmux sessions with pane-title summary.
# Format mirrors set-titles-string from common/tmux/tmux.conf so the same
# pane-title rendering shows up here.
tls() {
  tmux list-sessions -F '#{session_name}  #{?session_attached,●,○}  #{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
    | sed 's/ | $//'
}
