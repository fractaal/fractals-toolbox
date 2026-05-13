# tjoin — case-insensitive substring match a tmux session by name or pane title,
# then switch to it (switch-client inside tmux, attach from outside).
# Usage: tjoin <pattern>
#        tj    <pattern>
tjoin() {
  if (( $# == 0 )); then
    echo "Usage: tjoin <pattern>" >&2
    return 1
  fi

  local pattern="${(L)1}"
  local current_session=""
  if [[ -n "$TMUX" ]]; then
    current_session="$(tmux display-message -p '#{client_session}' 2>/dev/null || true)"
  fi
  local -a session_matches title_matches matches
  local name titles lower_name lower_titles m

  while IFS=$'\t' read -r name titles; do
    lower_name="${(L)name}"
    lower_titles="${(L)titles}"
    if [[ "$lower_name" == *"$pattern"* ]]; then
      session_matches+=("${name}"$'\t'"${titles}")
    elif [[ "$name" != "$current_session" && "$lower_titles" == *"$pattern"* ]]; then
      title_matches+=("${name}"$'\t'"${titles}")
    fi
  done < <(tmux list-sessions -F '#{session_name}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }')

  # Prefer stable session ids/names over volatile pane titles. Also do not let
  # the current pane title match the just-run command, e.g. `tjoin 758`.
  if (( ${#session_matches[@]} > 0 )); then
    matches=("${session_matches[@]}")
  else
    matches=("${title_matches[@]}")
  fi

  local n=${#matches[@]}
  if (( n == 0 )); then
    echo "tjoin: no session matches '$1'" >&2
    return 1
  elif (( n > 1 )); then
    echo "tjoin: '$1' is ambiguous, matches $n sessions:" >&2
    for m in "${matches[@]}"; do
      name="${m%%$'\t'*}"
      titles="${m#*$'\t'}"
      titles="${titles% | }"
      echo "  $name  $titles" >&2
    done
    return 1
  fi

  name="${matches[1]%%$'\t'*}"
  titles="${matches[1]#*$'\t'}"
  titles="${titles% | }"

  echo "Joining $name \"$titles\""

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$name"
  else
    tmux attach -t "$name"
  fi
}

alias tj=tjoin
