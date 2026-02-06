if [[ -r "$HOME/.fractals-toolbox/zsh/hosts.zsh" ]]; then
  source "$HOME/.fractals-toolbox/zsh/hosts.zsh"
fi

__sshsend_usage() {
  cat <<'EOF'
Usage:
  sshsend <host-alias> <local-file-or-folder>
  sshsend --list-hosts
  sshsend --help

Examples:
  sshsend saturn-02 ./some-file.txt
  sshsend saturn-02 ./some-folder
EOF
}

__sshsend_normalize_source_path() {
  local source_path="$1"

  if [[ -d "$source_path" ]]; then
    while [[ "$source_path" != "/" && "$source_path" == */ ]]; do
      source_path="${source_path%/}"
    done
  fi

  print -- "$source_path"
}

sshsend() {
  if (( $# == 0 )); then
    __sshsend_usage
    return 1
  fi

  case "$1" in
    -h|--help)
      __sshsend_usage
      return 0
      ;;
    --list-hosts)
      __fractal_list_host_aliases
      return $?
      ;;
  esac

  if [[ "$1" == -* ]]; then
    echo "Unknown option '$1'." >&2
    __sshsend_usage
    return 1
  fi

  if (( $# != 2 )); then
    __sshsend_usage
    return 1
  fi

  local host_alias="$1"
  local source_path="$2"
  local source_name target remote_destination

  if [[ ! -e "$source_path" ]]; then
    echo "Local path '${source_path}' does not exist." >&2
    return 1
  fi

  source_path="$(__sshsend_normalize_source_path "$source_path")"
  source_name="${source_path:t}"

  if ! target="$(__fractal_resolve_host_alias "$host_alias")"; then
    echo "Unknown host alias '${host_alias}'." >&2
    __fractal_list_host_aliases
    return 1
  fi

  remote_destination="${target}:~/Downloads/"
  echo "Sending '${source_name}' to ${host_alias} (${target})..."

  if command -v rsync >/dev/null 2>&1; then
    rsync -azP -e ssh -- "$source_path" "$remote_destination"
  else
    if [[ -d "$source_path" ]]; then
      scp -r "$source_path" "$remote_destination"
    else
      scp "$source_path" "$remote_destination"
    fi
  fi

  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "Transfer failed (exit ${exit_code})." >&2
    return "$exit_code"
  fi

  echo "Done."
}

_sshsend() {
  _arguments -C \
    '(-h --help)'{-h,--help}'[show usage]' \
    '--list-hosts[list configured host aliases]' \
    '1:host alias:__fractal_complete_host_aliases' \
    '2:local file or folder:_files -/'
}

if (( $+functions[compdef] )); then
  compdef _sshsend sshsend
fi
