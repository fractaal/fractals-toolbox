if [[ -n "${__FRACTAL_HOSTS_ZSH_LOADED:-}" ]]; then
  return 0
fi
typeset -g __FRACTAL_HOSTS_ZSH_LOADED=1

__fractal_load_host_aliases() {
  typeset -gA FRACTAL_HOST_ALIASES
  FRACTAL_HOST_ALIASES=()

  if [[ -r "$HOME/.fractals-toolbox/zsh/hosts.config.zsh" ]]; then
    source "$HOME/.fractals-toolbox/zsh/hosts.config.zsh"
  fi

  if [[ -r "$HOME/.fractals-toolbox/zsh/hosts.local.zsh" ]]; then
    source "$HOME/.fractals-toolbox/zsh/hosts.local.zsh"
  fi

  # Optional private overrides for shared host aliases.
  if [[ -r "$HOME/.fractals-toolbox-private/personal/hosts.config.zsh" ]]; then
    source "$HOME/.fractals-toolbox-private/personal/hosts.config.zsh"
  fi

  if [[ "${(t)FRACTAL_HOST_ALIASES}" != *association* ]]; then
    typeset -gA FRACTAL_HOST_ALIASES
  fi
}

__fractal_load_host_aliases

__fractal_resolve_host_alias() {
  local host_alias="$1"
  __fractal_load_host_aliases
  local target="${FRACTAL_HOST_ALIASES[$host_alias]-}"

  if [[ -z "$target" && -n "${SSHTUNNEL_HOSTS[$host_alias]-}" ]]; then
    target="${SSHTUNNEL_HOSTS[$host_alias]}"
  fi

  [[ -n "$target" ]] || return 1
  print -- "$target"
}

__fractal_list_host_aliases() {
  local host_alias target
  local -a keys

  __fractal_load_host_aliases

  keys=(${(ok)FRACTAL_HOST_ALIASES} ${(ok)SSHTUNNEL_HOSTS})
  keys=(${(ou)keys})

  if (( ${#keys[@]} == 0 )); then
    echo "No host aliases configured."
    return 1
  fi

  echo "Configured hosts:"
  for host_alias in "${keys[@]}"; do
    target="${FRACTAL_HOST_ALIASES[$host_alias]-}"
    if [[ -z "$target" && -n "${SSHTUNNEL_HOSTS[$host_alias]-}" ]]; then
      target="${SSHTUNNEL_HOSTS[$host_alias]}"
    fi
    echo "  - ${host_alias} -> ${target}"
  done
}

__fractal_complete_host_aliases() {
  local host_alias target
  local -a keys host_specs

  __fractal_load_host_aliases

  keys=(${(ok)FRACTAL_HOST_ALIASES} ${(ok)SSHTUNNEL_HOSTS})
  keys=(${(ou)keys})

  for host_alias in "${keys[@]}"; do
    target="${FRACTAL_HOST_ALIASES[$host_alias]-}"
    if [[ -z "$target" && -n "${SSHTUNNEL_HOSTS[$host_alias]-}" ]]; then
      target="${SSHTUNNEL_HOSTS[$host_alias]}"
    fi
    host_specs+=("${host_alias}:${target}")
  done

  _describe -t host_aliases 'host alias' host_specs
}
