# fractals-toolbox

Personal shell utilities and tooling. Sourced from `~/.zshrc` (or equivalent).

## Setup

Source the main zshrc from your shell config:

```zsh
[[ -r "$HOME/.fractals-toolbox/zsh/zshrc" ]] && source "$HOME/.fractals-toolbox/zsh/zshrc"
```

## What's included

### zsh/zshrc

| Name | Type | Description |
|------|------|-------------|
| `lidsleep` | function | Toggle macOS lid-sleep via `pmset disablesleep` (on/off/status, or toggle) |
| `portkill` | function | Kill processes bound to one or more local ports (`portkill 3000 8080`) |
| `renice-discord` | function | Set all Discord processes to lowest CPU priority (niceness 20) |
| `claude` | alias | Runs `claude --dangerously-skip-permissions` by default |

### zsh/hosts.zsh

Named host-alias system — define friendly names for SSH targets in `hosts.config.zsh` or `hosts.local.zsh` (gitignored).

| Command | Description |
|---------|-------------|
| `h <alias>` | SSH into a host alias |
| `h --list` | List all configured host aliases |

### zsh/sshtunnel.zsh

Persistent SSH tunnel manager with auto-reconnect.

### zsh/sshsend.zsh

Quick file transfer to remote hosts via `scp`, integrated with host aliases.

### deploy/

Deployment scripts.
