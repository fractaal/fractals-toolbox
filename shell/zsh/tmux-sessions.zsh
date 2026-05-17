# Shared tmux session helpers for tls/tjoin/tkill/tquit family commands.

_fractals_tmux_session_rows() {
  local helper="$HOME/.fractals-toolbox/common/bin/tmux-session-rows"
  if [[ -x "$helper" ]]; then
    "$helper" "$@"
  else
    tmux list-sessions -F '#{session_name}	#{?session_attached,●,○}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }' \
      | sed 's/ | $//'
  fi
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

_fractals_tmux_kill_picker() {
  local force=0
  if [[ "${1:-}" == "--force" ]]; then
    force=1
    shift
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "tkill: fzf is required for the TUI picker." >&2
    return 127
  fi

  local helper="$HOME/.fractals-toolbox/common/bin/tmux-session-rows"
  if [[ ! -x "$helper" ]]; then
    echo "tkill: missing $helper" >&2
    return 1
  fi

  local -a row_args
  row_args=()
  if (( ! force )); then
    row_args+=(--exclude-current)
  fi

  local rows query reload_cmd header
  rows="$($helper "${row_args[@]}" 2>/dev/null)" || true
  if [[ -z "$rows" ]]; then
    if (( force )); then
      echo "tkill: no tmux sessions found." >&2
    else
      echo "tkill: no killable sessions found (current session is hidden; use --force to include it)." >&2
    fi
    return 1
  fi

  query="$*"
  reload_cmd="$(printf '%q ' "$helper" "${row_args[@]}")"
  header="enter kill highlighted • ctrl-r refresh • esc done"
  if (( ! force )); then
    header+=" • current session hidden (--force includes it)"
  fi

  printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --prompt='tkill> ' \
    --height=80% \
    --layout=reverse \
    --border \
    --header="$header" \
    --bind="enter:execute-silent(tmux kill-session -t {1})+reload($reload_cmd)" \
    --bind="ctrl-r:reload($reload_cmd)" \
    ${query:+--query="$query"} \
    >/dev/null
}

_fractals_tmux_idle_session() {
  local helper="$HOME/.fractals-toolbox/common/bin/tmux-idle-session"
  [[ -x "$helper" ]] || return 1
  "$helper" "$@"
}
