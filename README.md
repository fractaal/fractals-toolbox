# fractals-toolbox

Personal shell utilities and tooling. Sourced from `~/.zshrc` (or equivalent).

## Setup

```bash
git clone https://github.com/fractaal/fractals-toolbox.git ~/.fractals-toolbox
bash ~/.fractals-toolbox/deploy/install.sh
```

Requires `bash` and `python3` (the zsh branch uses python3 for safe in-place `~/.zshrc` edits).

The installer detects what's on the machine and applies the matching wiring:

- **tmux** (always): symlinks `~/.tmux.conf` to `common/tmux/tmux.conf`. Backs up any pre-existing regular file as `~/.tmux.conf.pre-fractals.<timestamp>.bak`. A pre-existing symlink pointing somewhere else is replaced without backup (the previous target is logged).
- **zsh** (when `~/.zshrc` exists): inserts/updates marker blocks in `~/.zshrc` that source `shell/zsh/omz-plugins.zsh` and `shell/zsh/zshrc`. Removes the redundant inline tmux-autospawn block (toolbox now owns it).
- **fish** (when `command -v fish` succeeds): symlinks `shell/fish/fractals-toolbox.fish` into `~/.config/fish/conf.d/`, where fish auto-loads it on every interactive session.

Re-runs are idempotent — it's safe to invoke after `git pull`. A timestamped backup of `~/.zshrc` is written every time the file actually changes.

### Manual zsh-only setup (alternative)

If you'd rather skip the installer and only want the zsh side:

```zsh
[[ -r "$HOME/.fractals-toolbox/shell/zsh/zshrc" ]] && source "$HOME/.fractals-toolbox/shell/zsh/zshrc"
```

## What's included

### common/tmux/tmux.conf

Shared tmux configuration — read by tmux regardless of shell or OS. The deploy installer will symlink `~/.tmux.conf` to this file. Sets mouse on, vi-mode keys, double-lined pane borders with a top status row showing pane index, title, and running command, a `C-b T` keybind to rename the current pane title, and forwards pane titles up to the outer terminal (kitty tab bar) so multi-pane sessions stay legible.

### common/bin

Portable commands added to `PATH` by the zsh/fish entry points.

| Command | Description |
|---------|-------------|
| `qmd` | Local qmd wrapper/serializer |
| `sshtui` | Interactive SSH port-tunnel TUI for discovering and forwarding remote listening ports |
| `ytmp3` | Download any yt-dlp-supported URL as a highest-quality MP3 (`ytmp3 -d ~/Music <url>`) |

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

### common/sshtui

Interactive SSH port-tunnel TUI. Pick a host from `~/.ssh/config` or toolbox host aliases, scan remote listening ports live, and open/kill local forwards from the terminal.

### shell/zsh/sshtunnel.zsh

Persistent SSH tunnel manager with auto-reconnect.

### shell/zsh/sshsend.zsh

Quick file transfer to remote hosts via `scp`, integrated with host aliases.

### shell/{zsh,fish}/tmux-autospawn.{zsh,fish}

Auto-spawns a fresh `term-$pid` tmux session for every new interactive terminal window. Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing. Sourced last by each shell's umbrella because it `exec`s tmux, replacing the shell process.

### shell/{zsh,fish}/tls.{zsh,fish}

Defines a `tls` function — pane-title-aware tmux session lister. Output: `<session>  ●/○  <pane-title summary>` per session, where the title format mirrors `set-titles-string` from the tmux config so what kitty shows in its tab bar and what `tls` prints for that session match.

### shell/{zsh,fish}/tjoin.{zsh,fish}

Defines `tjoin <pattern>` (alias `tj`) — case-insensitive substring match against `session_name + pane titles`, then switches your tmux client to the unique match (`switch-client` inside tmux, `attach` from outside). 0 matches errors; >1 matches list candidates so you can be more specific. Confirmation: `Joining term-389741 "✳ aria-no-result-bogus-recovery-bug"`.

### shell/fish/fractals-toolbox.fish

Fish entry point. The deploy installer symlinks this into `~/.config/fish/conf.d/`; fish auto-loads everything in that dir. Sources the fish modules above in dependency order.

### deploy/

Deployment scripts.

## Known issues

- `~/.bun/bin/qmd` is a symlink that may point at the pre-restructure
  path `~/.fractals-toolbox/bin/qmd`. After this restructure the wrapper
  lives at `~/.fractals-toolbox/common/bin/qmd`. Repoint the symlink
  manually if you rely on it: `ln -sf ~/.fractals-toolbox/common/bin/qmd ~/.bun/bin/qmd`.
