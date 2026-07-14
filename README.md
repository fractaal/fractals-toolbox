# fractals-toolbox

Personal shell utilities and tooling. Sourced from `~/.zshrc` (or equivalent).

## Setup

```bash
git clone https://github.com/fractaal/fractals-toolbox.git ~/.fractals-toolbox
bash ~/.fractals-toolbox/deploy/install.sh
```

Requires `bash` and `python3` (the zsh branch uses python3 for safe in-place `~/.zshrc` edits). The tmux session TUI pickers also require `fzf`.

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
| `replace-text` | Case-preserving whole-token replace in a file or directory tree, with automatic backup (`replace-text <path> <from> <to>`) |
| `sshtui` | Interactive SSH port-tunnel TUI for discovering and forwarding remote listening ports |
| `ytmp3` | Download any yt-dlp-supported URL as a highest-quality MP3 (`ytmp3 -d ~/Music <url>`) |

### shell/zsh/zshrc

| Name | Type | Description |
|------|------|-------------|
| `lidsleep` | function | Toggle macOS lid-sleep via `pmset disablesleep` (on/off/status, or toggle) |
| `portkill` | function | Kill processes bound to one or more local ports (`portkill 3000 8080`) |
| `renice-discord` | function | Set all Discord processes to lowest CPU priority (niceness 20) |
| `claude` | alias | Runs `claude --dangerously-skip-permissions` by default |

### common/bin

Portable commands added to `PATH` by the zsh/fish entry points.

| Command | Description |
|---------|-------------|
| `mac-stream-mode` | Stop Sunshine, switch DP-8 to `3024x1964@60` scale `1.33`, then start Sunshine |
| `native-monitor-mode` | Stop Sunshine, restore DP-8 to `3440x1440@180` scale `1`, then start Sunshine |
| `hypr-recover` | From Hyprland's safe-mode terminal, load the normal config and restart Quickshell |
| `tjoin` / `tj` / `tjoin-tui` / `tjt` | Join tmux sessions by direct fuzzy match, or via `fzf` picker |
| `tkill` / `tk` / `tkill-tui` / `tkt` | Kill tmux sessions by direct fuzzy match, or repeatedly via `fzf` picker |
| `tquit` / `tq` / `texit` | Switch to an idle tmux session, then kill the current one |
| `tmux-session-rows` | Internal helper for pane-title-aware session picker rows |
| `tmux-idle-session` | Internal helper to find/create detached idle `term-*` sessions |
| `tmux-prune-idle-sessions` | Internal helper to garbage-collect detached idle `term-*` sessions |

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

Auto-attaches a new interactive terminal window to an existing detached idle `term-*` tmux session when one is available; otherwise spawns a fresh `term-$pid` session. Skips inside an existing tmux session, in non-interactive shells, and when tmux is missing. Sourced last by each shell's umbrella because it `exec`s tmux, replacing the shell process.

Detached idle `term-*` sessions are garbage-collected by tmux hooks after 60 seconds. "Idle" means one window, one pane, no attached clients, and the pane foreground command is a shell.

### shell/{zsh,fish}/tls.{zsh,fish}

Defines a `tls` function — pane-title-aware tmux session lister. Output: `<session>  ●/○  <pane-title summary>` per session, where the title format mirrors `set-titles-string` from the tmux config so what kitty shows in its tab bar and what `tls` prints for that session match.

### shell/{zsh,fish}/tjoin.{zsh,fish}

Defines `tjoin [pattern]` (alias `tj`) — with a pattern, case-insensitive substring match against `session_name + pane titles`, then switches your tmux client to the unique match (`switch-client` inside tmux, `attach` from outside). 0 matches errors; >1 matches list candidates so you can be more specific. With no args, opens an `fzf` picker over the same session/title summary. Confirmation: `Joining term-389741 "✳ fix-login-redirect"`.

Also defines `tjoin-tui [initial-query]` (alias `tjt`) as an explicit picker entrypoint.

### shell/{zsh,fish}/tkill.{zsh,fish}

Defines `tkill [--force] [pattern]` (alias `tk`) — same matching rules as `tjoin`, but kills the unique tmux session. With no pattern, opens an `fzf` picker where Enter kills the highlighted session, reloads the same list, and stays open until Escape. The current session is hidden unless `--force` is passed. Confirmation for direct pattern kills: `Killing term-389741 "✳ fix-login-redirect"`.

Also defines `tkill-tui [--force] [initial-query]` (alias `tkt`) as an explicit picker entrypoint.

### shell/{zsh,fish}/tquit.{zsh,fish}

Defines `tquit` (aliases `tq`, `texit`) — from inside tmux, switch the current client to a detached idle `term-*` session (or create one in the current directory), then kill the original session. This is the safe "exit this tmux session without closing my terminal/SSH" command.

### shell/fish/fractals-toolbox.fish

Fish entry point. The deploy installer symlinks this into `~/.config/fish/conf.d/`; fish auto-loads everything in that dir. Sources the fish modules above in dependency order.

### deploy/

Deployment scripts.

## Known issues

- `~/.bun/bin/qmd` is a symlink that may point at the pre-restructure
  path `~/.fractals-toolbox/bin/qmd`. After this restructure the wrapper
  lives at `~/.fractals-toolbox/common/bin/qmd`. Repoint the symlink
  manually if you rely on it: `ln -sf ~/.fractals-toolbox/common/bin/qmd ~/.bun/bin/qmd`.
