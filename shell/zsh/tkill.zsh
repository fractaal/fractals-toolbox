# tkill — case-insensitive substring match a tmux session by name or pane title,
# then kill the unique match.
# Usage: tkill [--force] [pattern]
#        tk    [--force] [pattern]
#        tkill-tui [--force] [initial-query]
#        tkt       [--force] [initial-query]

if ! whence -w _fractals_tmux_session_rows >/dev/null 2>&1 \
  && [[ -r "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh" ]]; then
  source "$HOME/.fractals-toolbox/shell/zsh/tmux-sessions.zsh"
fi

_fractals_tkill_kill_session() {
  local name="$1"
  local titles="$2"

  echo "Killing $name \"$titles\""
  tmux kill-session -t "$name"
}

tkill() {
  local force=0
  if (( $# > 0 )) && [[ "$1" == "-f" || "$1" == "--force" ]]; then
    force=1
    shift
  fi

  if (( $# == 0 )); then
    if (( force )); then
      tkill-tui --force
    else
      tkill-tui
    fi
    return $?
  fi

  local query="$*"
  local pattern="${(L)query}"
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
  # the current pane title match the just-run command, e.g. `tkill 758`.
  if (( ${#session_matches[@]} > 0 )); then
    matches=("${session_matches[@]}")
  else
    matches=("${title_matches[@]}")
  fi

  local n=${#matches[@]}
  if (( n == 0 )); then
    echo "tkill: no session matches '$query'" >&2
    return 1
  elif (( n > 1 )); then
    echo "tkill: '$query' is ambiguous, matches $n sessions:" >&2
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

  if [[ -n "$current_session" && "$name" == "$current_session" && "$force" -ne 1 ]]; then
    echo "tkill: refusing to kill current session '$name' (use --force to override)." >&2
    return 1
  fi

  _fractals_tkill_kill_session "$name" "$titles"
}

tkill-tui() {
  local force=0
  if (( $# > 0 )) && [[ "$1" == "-f" || "$1" == "--force" ]]; then
    force=1
    shift
  fi

  local row name titles current_session answer
  row="$(_fractals_tmux_pick_session tkill 'select a tmux session to kill' "$@")" || return $?
  name="$(_fractals_tmux_row_name "$row")"
  titles="$(_fractals_tmux_row_titles "$row")"
  current_session="$(_fractals_tmux_current_session)"

  if [[ -n "$current_session" && "$name" == "$current_session" && "$force" -ne 1 ]]; then
    echo "tkill-tui: refusing to kill current session '$name' (use --force to override)." >&2
    return 1
  fi

  printf "Kill tmux session '%s'? [y/N] " "$name" >&2
  read -r answer
  case "${(L)answer}" in
    y|yes) ;;
    *) echo "Cancelled"; return 1 ;;
  esac

  _fractals_tkill_kill_session "$name" "$titles"
}

alias tk=tkill
alias tkt='tkill-tui'
