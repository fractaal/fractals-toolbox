# fractals-toolbox

Personal shell utilities and tooling. Sourced from `~/.zshrc` (or equivalent).

## Setup

Source the main zshrc from your shell config:

```zsh
[[ -r "$HOME/.fractals-toolbox/shell/zsh/zshrc" ]] && source "$HOME/.fractals-toolbox/shell/zsh/zshrc"
```

## What's included

### common/tmux/tmux.conf

Shared tmux configuration — read by tmux regardless of shell or OS. The deploy installer will symlink `~/.tmux.conf` to this file. Sets mouse on, vi-mode keys, double-lined pane borders with a top status row showing pane index, title, and running command, a `C-b T` keybind to rename the current pane title, and forwards pane titles up to the outer terminal (kitty tab bar) so multi-pane sessions stay legible.

### shell/zsh/zshrc

| Name | Type | Description |
|------|------|-------------|
| `lidsleep` | function | Toggle macOS lid-sleep via `pmset disablesleep` (on/off/status, or toggle) |
| `portkill` | function | Kill processes bound to one or more local ports (`portkill 3000 8080`) |
| `renice-discord` | function | Set all Discord processes to lowest CPU priority (niceness 20) |
| `claude` | alias | Runs `claude --dangerously-skip-permissions` by default |

### shell/zsh/hosts.zsh

Named host-alias system — define friendly names for SSH targets in `hosts.config.zsh` or `hosts.local.zsh` (gitignored).

| Command | Description |
|---------|-------------|
| `h <alias>` | SSH into a host alias |
| `h --list` | List all configured host aliases |

### shell/zsh/sshtunnel.zsh

Persistent SSH tunnel manager with auto-reconnect.

### shell/zsh/sshsend.zsh

Quick file transfer to remote hosts via `scp`, integrated with host aliases.

### shell/{zsh,fish}/tmux-autospawn.{zsh,fish}

Auto-spawns a fresh `term-$pid` tmux session for every new interactive terminal window. Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing. Sourced last by each shell's umbrella because it `exec`s tmux, replacing the shell process.

### shell/{zsh,fish}/tls.{zsh,fish}

Defines a `tls` function — pane-title-aware tmux session lister. Output: `<session>  ●/○  <pane-title summary>` per session, where the title format mirrors `set-titles-string` from the tmux config so what kitty shows in its tab bar and what `tls` prints for that session match.

### shell/fish/fractals-toolbox.fish

Fish entry point. The deploy installer symlinks this into `~/.config/fish/conf.d/`; fish auto-loads everything in that dir. Sources the fish modules above in dependency order.

### deploy/

Deployment scripts.

## Known issues

- `~/.bun/bin/qmd` is a symlink that may point at the pre-restructure
  path `~/.fractals-toolbox/bin/qmd`. After this restructure the wrapper
  lives at `~/.fractals-toolbox/common/bin/qmd`. Repoint the symlink
  manually if you rely on it: `ln -sf ~/.fractals-toolbox/common/bin/qmd ~/.bun/bin/qmd`.
