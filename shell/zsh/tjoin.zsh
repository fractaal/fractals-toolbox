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
  local -a matches
  local name titles haystack m

  while IFS=$'\t' read -r name titles; do
    haystack="${(L)name}"$'\t'"${(L)titles}"
    if [[ "$haystack" == *"$pattern"* ]]; then
      matches+=("${name}"$'\t'"${titles}")
    fi
  done < <(tmux list-sessions -F '#{session_name}	#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }')

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
