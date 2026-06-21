# sshtui

Interactive SSH port-tunnel TUI. Point it at a host, see what's listening
(refreshed live), and press <kbd>↵</kbd> to open a local tunnel to any port —
same local port by default. Open and kill as many as you like; everything is
torn down cleanly on quit.

It's the dynamic/exploratory companion to `sshtunnel` (which is static and
profile-driven). `sshtunnel` is for tunnels you already know you want;
`sshtui` is for discovering and grabbing ports interactively.

## Usage

```
sshtui [host-or-alias]
```

`sshtui` is on `$PATH` via `common/bin`. With no argument it shows a picker of
hosts from `~/.ssh/config` and your toolbox host aliases (`hosts.config.zsh` /
`hosts.local.zsh`). With an argument it resolves toolbox aliases, otherwise
passes the name straight to ssh.

### Keys

| Key | Action |
|-----|--------|
| <kbd>↑</kbd>/<kbd>↓</kbd> or <kbd>j</kbd>/<kbd>k</kbd> | move selection |
| <kbd>↵</kbd> / <kbd>space</kbd> | tunnel the selected port (or kill it if already tunneled) |
| <kbd>c</kbd> | open with a custom local port |
| <kbd>a</kbd> | tunnel an arbitrary remote port (not in the list) |
| <kbd>r</kbd> | refresh the port scan now |
| <kbd>K</kbd> | kill all tunnels |
| <kbd>q</kbd> / <kbd>Ctrl-C</kbd> | quit (tears down all tunnels + the connection) |

If the default local port is busy, it transparently picks the next free one and
tells you in the status line.

## How it works

- One SSH **ControlMaster** is opened up front (in the foreground, so any
  passphrase/agent prompt works), then reused for everything — so you
  authenticate once and repeated scans are instant.
- **Discovery** runs `ss -tlnp` (falling back to `netstat`) over the master
  every 5s, wrapped in `sh -c` so it's shell-agnostic on the remote.
- **Tunnels** are registered on the master with `ssh -O forward` and removed
  with `-O cancel`. The forward target is derived from where the port is
  actually bound — a service on IPv6 loopback (`[::1]`) is forwarded to `::1`,
  not `127.0.0.1`, so loopback-only dev servers actually work.

Zero npm dependencies. Runs on node (preferred) or bun.

## Tests

```
node test-parse.mjs   # parsing + forward-target unit tests
```
