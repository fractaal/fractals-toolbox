if [[ -n "${__FRACTAL_YTDL_ZSH_LOADED:-}" ]]; then
  return 0
fi
typeset -g __FRACTAL_YTDL_ZSH_LOADED=1

# ---------------------------------------------------------------------------
# Path alias loader (mirrors hosts.zsh pattern)
# ---------------------------------------------------------------------------

__ytdl_load_path_aliases() {
  typeset -gA FRACTAL_YTDL_PATH_ALIASES
  FRACTAL_YTDL_PATH_ALIASES=()

  if [[ -r "$HOME/.fractals-toolbox/zsh/ytdl.config.zsh" ]]; then
    source "$HOME/.fractals-toolbox/zsh/ytdl.config.zsh"
  fi

  if [[ -r "$HOME/.fractals-toolbox/zsh/ytdl.local.zsh" ]]; then
    source "$HOME/.fractals-toolbox/zsh/ytdl.local.zsh"
  fi

  if [[ -r "$HOME/.fractals-toolbox-private/personal/ytdl.config.zsh" ]]; then
    source "$HOME/.fractals-toolbox-private/personal/ytdl.config.zsh"
  fi

  if [[ "${(t)FRACTAL_YTDL_PATH_ALIASES}" != *association* ]]; then
    typeset -gA FRACTAL_YTDL_PATH_ALIASES
  fi
}

__ytdl_load_path_aliases

# ---------------------------------------------------------------------------
# Resolve a path argument: alias → absolute/relative path → ~/Downloads
# ---------------------------------------------------------------------------

__ytdl_resolve_output_dir() {
  local arg="$1"

  # No argument — default to ~/Downloads.
  if [[ -z "$arg" ]]; then
    print -- "$HOME/Downloads"
    return 0
  fi

  # Check path aliases first.
  __ytdl_load_path_aliases
  local aliased="${FRACTAL_YTDL_PATH_ALIASES[$arg]-}"
  if [[ -n "$aliased" ]]; then
    # Expand ~ / $HOME that may be stored in the alias value.
    print -- "${aliased/#\~/$HOME}"
    return 0
  fi

  # Literal path (absolute or relative).
  if [[ "$arg" == /* ]]; then
    print -- "$arg"
  else
    print -- "$PWD/$arg"
  fi
}

# ---------------------------------------------------------------------------
# List configured path aliases
# ---------------------------------------------------------------------------

__ytdl_list_path_aliases() {
  __ytdl_load_path_aliases

  local -a keys
  keys=(${(ok)FRACTAL_YTDL_PATH_ALIASES})

  if (( ${#keys[@]} == 0 )); then
    echo "No path aliases configured."
    return 1
  fi

  echo "Configured path aliases:"
  for k in "${keys[@]}"; do
    echo "  ${k} -> ${FRACTAL_YTDL_PATH_ALIASES[$k]}"
  done
  echo ""
  echo "Default (no alias): ~/Downloads"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

__ytdl_usage() {
  cat <<'EOF'
Usage:
  ytdl <url> [destination]
  ytdl --list-aliases
  ytdl --help

destination can be:
  (omitted)          → ~/Downloads
  a path alias       → resolved from ytdl.config.zsh / ytdl.local.zsh
  a relative path    → resolved from $PWD
  an absolute path   → used as-is

Examples:
  ytdl "https://youtube.com/watch?v=..."
  ytdl "https://youtube.com/watch?v=..." stock-music
  ytdl "https://youtube.com/watch?v=..." ~/Music/Samples
  ytdl "https://youtube.com/watch?v=..." .
EOF
}

# ---------------------------------------------------------------------------
# Main command
# ---------------------------------------------------------------------------

ytdl() {
  if (( $# == 0 )); then
    __ytdl_usage
    return 1
  fi

  case "$1" in
    -h|--help)
      __ytdl_usage
      return 0
      ;;
    --list-aliases)
      __ytdl_list_path_aliases
      return $?
      ;;
  esac

  if [[ "$1" == -* ]]; then
    echo "Unknown option '$1'." >&2
    __ytdl_usage
    return 1
  fi

  local url="$1"
  local dest_arg="${2:-}"
  local output_dir

  output_dir="$(__ytdl_resolve_output_dir "$dest_arg")"

  if [[ ! -d "$output_dir" ]]; then
    echo "Creating directory: ${output_dir}"
    mkdir -p "$output_dir" || {
      echo "Failed to create directory '${output_dir}'." >&2
      return 1
    }
  fi

  echo "Downloading mp3 → ${output_dir}"
  yt-dlp \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    --embed-thumbnail \
    --embed-metadata \
    --output "${output_dir}/%(title)s.%(ext)s" \
    "$url"

  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "yt-dlp failed (exit ${exit_code})." >&2
    return "$exit_code"
  fi

  echo "Done."
}

# ---------------------------------------------------------------------------
# Zsh completions
# ---------------------------------------------------------------------------

__ytdl_complete_path_aliases() {
  local -a keys alias_specs

  __ytdl_load_path_aliases
  keys=(${(ok)FRACTAL_YTDL_PATH_ALIASES})

  for k in "${keys[@]}"; do
    alias_specs+=("${k}:${FRACTAL_YTDL_PATH_ALIASES[$k]}")
  done

  _describe -t path_aliases 'path alias' alias_specs
}

__ytdl_complete_destination() {
  _alternative \
    'aliases:path alias:__ytdl_complete_path_aliases' \
    'directories:directory:_directories'
}

_ytdl() {
  _arguments -C \
    '(-h --help)'{-h,--help}'[show usage]' \
    '--list-aliases[list configured path aliases]' \
    '1:url:' \
    '2:destination:__ytdl_complete_destination'
}

if (( $+functions[compdef] )); then
  compdef _ytdl ytdl
fi
