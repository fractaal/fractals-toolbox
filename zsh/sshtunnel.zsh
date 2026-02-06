if [[ -r "$HOME/.fractals-toolbox/zsh/hosts.zsh" ]]; then
  source "$HOME/.fractals-toolbox/zsh/hosts.zsh"
fi

if [[ -r "$HOME/.fractals-toolbox/zsh/sshtunnel.config.zsh" ]]; then
  source "$HOME/.fractals-toolbox/zsh/sshtunnel.config.zsh"
fi

if [[ -r "$HOME/.fractals-toolbox/zsh/sshtunnel.local.zsh" ]]; then
  source "$HOME/.fractals-toolbox/zsh/sshtunnel.local.zsh"
fi

# Optional private overrides for host aliases/profiles.
if [[ -r "$HOME/.fractals-toolbox-private/personal/sshtunnel.config.zsh" ]]; then
  source "$HOME/.fractals-toolbox-private/personal/sshtunnel.config.zsh"
fi

__sshtunnel_usage() {
  cat <<'EOF'
Usage:
  sshtunnel <host-alias> [profile]
  sshtunnel --list-hosts
  sshtunnel --list-profiles
  sshtunnel --help

Examples:
  sshtunnel saturn-02
  sshtunnel saturn-02 next-and-api
EOF
}

__sshtunnel_list_hosts() {
  __fractal_list_host_aliases
}

__sshtunnel_profile_port_summary() {
  local profile_spec="$1"
  local -a pair_tokens local_ports
  local pair

  pair_tokens=(${=profile_spec})
  for pair in "${pair_tokens[@]}"; do
    if [[ "$pair" == <->:<-> ]]; then
      local_ports+=("${pair%%:*}")
    fi
  done

  if (( ${#local_ports[@]} == 0 )); then
    print -- "$profile_spec"
    return
  fi

  print -- "${(j:, :)local_ports}"
}

__sshtunnel_list_profiles() {
  local profile_name
  local summary
  local -a profile_names

  profile_names=(${(ok)SSHTUNNEL_PROFILES})
  if (( ${#profile_names[@]} == 0 )); then
    echo "No port profiles configured."
    echo "Add profiles in ~/.fractals-toolbox/zsh/sshtunnel.local.zsh"
    return 1
  fi

  echo "Configured profiles:"
  for profile_name in "${profile_names[@]}"; do
    summary="$(__sshtunnel_profile_port_summary "${SSHTUNNEL_PROFILES[$profile_name]}")"
    echo "  - ${profile_name} -> ${summary}"
  done
}

__sshtunnel_port_is_busy() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 1
  fi

  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

sshtunnel() {
  if (( $# == 0 )); then
    __sshtunnel_usage
    return 1
  fi

  case "$1" in
    -h|--help)
      __sshtunnel_usage
      return 0
      ;;
    --list-hosts)
      __sshtunnel_list_hosts
      return 0
      ;;
    --list-profiles)
      __sshtunnel_list_profiles
      return 0
      ;;
  esac

  if [[ "$1" == -* ]]; then
    echo "Unknown option '$1'." >&2
    __sshtunnel_usage
    return 1
  fi

  if [[ "${2-}" == "-h" || "${2-}" == "--help" ]]; then
    __sshtunnel_usage
    return 0
  fi

  if (( $# > 2 )); then
    echo "Too many arguments." >&2
    __sshtunnel_usage
    return 1
  fi

  local host_alias="$1"
  local profile_name="${2:-default}"
  local target
  local profile_spec="${SSHTUNNEL_PROFILES[$profile_name]-}"
  local reconnect_delay="${SSHTUNNEL_RECONNECT_DELAY:-3}"

  if (( $# == 1 )); then
    echo "No port profile selected. Using 'default'..."
  fi

  if ! target="$(__fractal_resolve_host_alias "$host_alias")"; then
    echo "Unknown host alias '${host_alias}'." >&2
    __sshtunnel_list_hosts
    return 1
  fi

  if [[ -z "$profile_spec" ]]; then
    echo "Unknown port profile '${profile_name}'." >&2
    __sshtunnel_list_profiles
    return 1
  fi

  local -a pair_tokens local_ports ssh_port_args
  local pair local_port remote_port

  pair_tokens=(${=profile_spec})
  if (( ${#pair_tokens[@]} == 0 )); then
    echo "Port profile '${profile_name}' has no port mappings." >&2
    return 1
  fi

  for pair in "${pair_tokens[@]}"; do
    if [[ "$pair" != <->:<-> ]]; then
      echo "Invalid port mapping '${pair}' in profile '${profile_name}'. Use local:remote." >&2
      return 1
    fi

    local_port="${pair%%:*}"
    remote_port="${pair##*:}"

    if __sshtunnel_port_is_busy "$local_port"; then
      echo "Local port ${local_port} is already in use; cannot start tunnel." >&2
      return 1
    fi

    local_ports+=("$local_port")
    ssh_port_args+=(-L "${local_port}:127.0.0.1:${remote_port}")
  done

  echo "Ports ${(j:, :)local_ports} tunneled"

  (
    trap 'exit 130' INT TERM
    local exit_code
    while true; do
      ssh \
        -N \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o TCPKeepAlive=yes \
        -o ConnectTimeout=10 \
        "${ssh_port_args[@]}" \
        "$target"

      exit_code=$?
      if (( exit_code == 130 || exit_code == 143 )); then
        exit 0
      fi

      echo "Tunnel dropped (exit ${exit_code}). Reconnecting in ${reconnect_delay}s..."
      sleep "$reconnect_delay"
    done
  )
}

__sshtunnel_complete_hosts() {
  __fractal_complete_host_aliases
}

__sshtunnel_complete_profiles() {
  local profile_name summary
  local -a profile_specs

  for profile_name in ${(ok)SSHTUNNEL_PROFILES}; do
    summary="$(__sshtunnel_profile_port_summary "${SSHTUNNEL_PROFILES[$profile_name]}")"
    profile_specs+=("${profile_name}:${summary}")
  done

  if (( ${#profile_specs[@]} == 0 )); then
    return 0
  fi

  _describe -t profiles 'port profile' profile_specs
}

_sshtunnel() {
  _arguments -C \
    '(-h --help)'{-h,--help}'[show usage]' \
    '--list-hosts[list configured host aliases]' \
    '--list-profiles[list configured port profiles]' \
    '1:host alias:__sshtunnel_complete_hosts' \
    '2:port profile:__sshtunnel_complete_profiles'
}

if (( $+functions[compdef] )); then
  compdef _sshtunnel sshtunnel
fi
