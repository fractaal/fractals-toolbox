# tjoin — case-insensitive substring match a tmux session by name or pane title,
# then switch to it (switch-client inside tmux, attach from outside).
# Usage: tjoin <pattern>
#        tj    <pattern>
#        tjoin-tui [initial-query]
#        tjt       [initial-query]

if ! whence -w _fractals_tmux_session_rows >/dev/null 2>&1 \
  && [[ -r "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh" ]]; then
  source "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh"
fi

_fractals_tjoin_switch_to_session() {
  local name="$1"
  local titles="$2"

  echo "Joining $name \"$titles\""

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$name"
  else
    tmux attach -t "$name"
  fi
}

tjoin() {
  if (( $# == 0 )); then
    echo "Usage: tjoin <pattern>" >&2
    echo "       tjoin-tui [initial-query]" >&2
    return 1
  fi

  local pattern="${(L)1}"
  local current_session=""
  current_session="$(_fractals_tmux_current_session)"
  local -a session_matches title_matches matches
  local name titles lower_name lower_titles m

  while IFS=$'\t' read -r name _attached titles; do
    lower_name="${(L)name}"
    lower_titles="${(L)titles}"
    if [[ "$lower_name" == *"$pattern"* ]]; then
      session_matches+=("${name}"$'\t'"${titles}")
    elif [[ "$name" != "$current_session" && "$lower_titles" == *"$pattern"* ]]; then
      title_matches+=("${name}"$'\t'"${titles}")
    fi
  done < <(_fractals_tmux_session_rows)

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

  _fractals_tjoin_switch_to_session "$name" "$titles"
}

tjoin-tui() {
  local row name titles
  row="$(_fractals_tmux_pick_session tjoin 'select a tmux session to join' "$@")" || return $?
  name="$(_fractals_tmux_row_name "$row")"
  titles="$(_fractals_tmux_row_titles "$row")"

  _fractals_tjoin_switch_to_session "$name" "$titles"
}

alias tj=tjoin
alias tjt='tjoin-tui'
