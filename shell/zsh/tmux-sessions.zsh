# Shared tmux session helpers for tls/tjoin/tkill family commands.

_fractals_tmux_session_rows() {
  tmux list-sessions -F '#{session_name}	#{?session_attached,●,○}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
    | sed 's/ | $//'
}

_fractals_tmux_current_session() {
  if [[ -n "$TMUX" ]]; then
    tmux display-message -p '#{client_session}' 2>/dev/null || true
  fi
}

_fractals_tmux_row_name() {
  local row="$1"
  printf '%s' "${row%%$'\t'*}"
}

_fractals_tmux_row_titles() {
  local row="$1"
  local rest="${row#*$'\t'}"
  if [[ "$rest" == "$row" ]]; then
    return 0
  fi

  rest="${rest#*$'\t'}"
  if [[ "$rest" == "$row" ]]; then
    return 0
  fi

  printf '%s' "${rest% | }"
}

_fractals_tmux_pick_session() {
  local prompt="$1"
  local header="$2"
  shift 2

  if ! command -v fzf >/dev/null 2>&1; then
    echo "$prompt: fzf is required for the TUI picker." >&2
    return 127
  fi

  local rows selected query
  query="$*"
  rows="$(_fractals_tmux_session_rows 2>/dev/null)" || true
  if [[ -z "$rows" ]]; then
    echo "$prompt: no tmux sessions found." >&2
    return 1
  fi

  local -a fzf_args
  fzf_args=(
    --delimiter=$'\t'
    --with-nth=1,2,3
    --prompt="$prompt> "
    --height=80%
    --layout=reverse
    --border
    --header="$header"
  )
  if [[ -n "$query" ]]; then
    fzf_args+=(--query="$query")
  fi

  selected="$(printf '%s\n' "$rows" | fzf "${fzf_args[@]}")" || return 130
  [[ -n "$selected" ]] || return 130
  printf '%s\n' "$selected"
}
