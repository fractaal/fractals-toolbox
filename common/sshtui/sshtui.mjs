#!/usr/bin/env node
// sshtui — interactive SSH port-tunnel TUI for fractals-toolbox.
//
// Point at a host, see what's listening (refreshed every few seconds), and
// press ↵ to open a local tunnel to any port (default: same local port).
// Open/kill as many as you like; everything is torn down cleanly on quit.
//
// Zero dependencies on purpose — the toolbox stays dep-free. Runs on node or
// bun. Discovery and tunnels ride a single SSH ControlMaster connection so
// repeated polls are instant and you only authenticate once.
//
// Companion to `sshtunnel` (static, profile-driven, auto-reconnect). This one
// is the dynamic/exploratory half: discover ports you didn't know were there.

import net from 'node:net';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';

// ─────────────────────────────────────────────────────────────────────────
// Config / constants
// ─────────────────────────────────────────────────────────────────────────

const REFRESH_MS = 5000;        // remote port re-scan interval
const REPAINT_MS = 400;         // UI tick (spinner, timers, tunnel-state promotion)

const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

// SSH options shared by every non-interactive client (discovery + tunnels).
// BatchMode=yes guarantees they NEVER prompt inside the alt-screen (which would
// corrupt the display); they simply ride the master or fail fast.
function clientOpts(sock) {
  return [
    '-o', 'BatchMode=yes',
    '-o', `ControlPath=${sock}`,
    '-o', 'ControlMaster=no',
  ];
}

// The remote command. Wrapped in `sh -c` so it parses identically regardless
// of the remote login shell (unixboat runs fish, which lacks `netstat` and
// historically differed on `||`). `ss -H` strips the header for clean parsing.
const REMOTE_SCAN =
  "sh -c 'ss -H -tlnp 2>/dev/null || ss -H -tln 2>/dev/null || " +
  "netstat -tlnp 2>/dev/null || netstat -tln 2>/dev/null'";

// ─────────────────────────────────────────────────────────────────────────
// Pure helpers (unit-tested in test-parse.mjs)
// ─────────────────────────────────────────────────────────────────────────

// Extract the listening port from a local-address token. Handles:
//   0.0.0.0:22 · 127.0.0.1:5432 · *:9993 · 127.0.0.53%lo:53
//   [::1]:4000 · [::]:5355 · [fd7a:115c:a1e0::f739:237e]:44119
export function extractPort(addr) {
  const idx = addr.lastIndexOf(':');
  if (idx === -1) return null;
  const n = Number.parseInt(addr.slice(idx + 1), 10);
  return Number.isInteger(n) && n > 0 && n <= 65535 ? n : null;
}

// Extract the bind address (everything before the final colon), stripping
// IPv6 brackets and interface-zone suffixes (e.g. "%lo").
export function extractBind(addr) {
  const idx = addr.lastIndexOf(':');
  let b = idx === -1 ? addr : addr.slice(0, idx);
  b = b.replace(/^\[/, '').replace(/\]$/, '');
  b = b.replace(/%.*$/, '');
  return b;
}

// Parse `ss`/`netstat` output into a deduped, sorted list of listening ports.
// Each entry: { port, binds: string[], proc: string|null }
export function parsePorts(raw) {
  const byPort = new Map();
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;

    let local = null;
    let proc = null;

    if (/^LISTEN\b/i.test(t)) {
      // ss:  LISTEN  recvq  sendq  LOCAL  PEER  [users:(("name",pid=..,..))]
      const parts = t.split(/\s+/);
      local = parts[3];
      const m = t.match(/users:\(\("([^"]+)"/);
      if (m) proc = m[1];
    } else if (/^tcp6?\b/i.test(t) && /\bLISTEN\b/.test(t)) {
      // netstat: tcp 0 0 LOCAL FOREIGN LISTEN [pid/prog]
      const parts = t.split(/\s+/);
      local = parts[3];
      const last = parts[parts.length - 1];
      const pm = last.match(/^\d+\/(.+)$/);
      if (pm) proc = pm[1];
    } else {
      continue;
    }

    if (!local) continue;
    const port = extractPort(local);
    if (port == null) continue;
    const bind = extractBind(local);

    if (!byPort.has(port)) byPort.set(port, { port, binds: new Set(), proc: null });
    const entry = byPort.get(port);
    entry.binds.add(bind);
    if (!entry.proc && proc) entry.proc = proc;
  }

  return [...byPort.values()]
    .map((e) => ({ port: e.port, binds: [...e.binds], proc: e.proc }))
    .sort((a, b) => a.port - b.port);
}

// Choose the address ssh should connect to on the remote side for a given
// port, derived from where it's actually bound. THIS IS LOAD-BEARING: a
// service on [::1] only (IPv6 loopback) is unreachable via 127.0.0.1, so a
// naive forward would silently fail with "connection refused".
export function forwardTarget(binds) {
  const has = (x) => binds.includes(x);
  if (has('0.0.0.0') || has('*')) return '127.0.0.1';
  const v4 = binds.find((b) => b.includes('.') && b !== '*');
  if (v4) return v4;                       // a real interface IP, reachable from remote itself
  if (has('::')) return '::1';             // v6 wildcard → v6 loopback works
  const v6 = binds.find((b) => b.includes(':'));
  if (v6) return v6;
  return '127.0.0.1';
}

// Build the `-L` forward spec, bracketing IPv6 targets.
export function forwardSpec(localPort, remotePort, binds) {
  const target = forwardTarget(binds);
  const host = target.includes(':') ? `[${target}]` : target;
  return `127.0.0.1:${localPort}:${host}:${remotePort}`;
}

// Summarize bind addresses for the UI, e.g. ["0.0.0.0","::"] → "0.0.0.0 +1".
export function bindSummary(binds) {
  if (binds.length === 0) return '';
  if (binds.length === 1) return binds[0];
  return `${binds[0]} +${binds.length - 1}`;
}

// ─────────────────────────────────────────────────────────────────────────
// Host resolution (ssh config + toolbox aliases) — files only, never `zsh -i`
// (the toolbox's tmux-autospawn module execs tmux on interactive shells).
// ─────────────────────────────────────────────────────────────────────────

function readIfExists(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return ''; }
}

function parseSshConfigHosts() {
  const raw = readIfExists(path.join(os.homedir(), '.ssh', 'config'));
  const hosts = [];
  for (const line of raw.split('\n')) {
    const m = line.match(/^\s*Host\s+(.+?)\s*$/i);
    if (!m) continue;
    for (const name of m[1].split(/\s+/)) {
      if (name && !name.includes('*') && !name.includes('?')) {
        hosts.push({ name, target: name, source: 'ssh' });
      }
    }
  }
  return hosts;
}

function stripShellComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '\\') { i++; continue; }
    if (quote) {
      if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === '#') {
      return line.slice(0, i);
    }
  }
  return line;
}

function splitShellWords(line) {
  const words = [];
  let word = '';
  let quote = null;
  let inWord = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '\\') {
      if (i + 1 < line.length) word += line[++i];
      inWord = true;
    } else if (quote) {
      if (ch === quote) quote = null;
      else word += ch;
      inWord = true;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      inWord = true;
    } else if (/\s/.test(ch)) {
      if (inWord) {
        words.push(word);
        word = '';
        inWord = false;
      }
    } else {
      word += ch;
      inWord = true;
    }
  }
  if (inWord) words.push(word);
  return words;
}

export function parseToolboxHostText(raw) {
  const hosts = [];
  let inAliasArray = false;
  const indexed = /^\s*(?:FRACTAL_HOST_ALIASES|SSHTUNNEL_HOSTS)\[([^\]]+)\]=(.+?)\s*$/;

  for (const rawLine of raw.split('\n')) {
    const line = stripShellComment(rawLine).trim();
    if (!line) continue;

    const m = line.match(indexed);
    if (m) {
      const name = splitShellWords(m[1])[0] ?? m[1].replace(/^["']|["']$/g, '');
      const target = splitShellWords(m[2])[0] ?? m[2].trim().replace(/^["']|["']$/g, '');
      if (name && target) hosts.push({ name, target });
      continue;
    }

    if (/^(?:FRACTAL_HOST_ALIASES|SSHTUNNEL_HOSTS)=\(\s*$/.test(line)) {
      inAliasArray = true;
      continue;
    }

    if (inAliasArray) {
      if (line === ')' || line.startsWith(')')) {
        inAliasArray = false;
        continue;
      }
      const words = splitShellWords(line);
      if (words.length >= 2) hosts.push({ name: words[0], target: words[1] });
    }
  }

  return hosts;
}

function parseToolboxHosts() {
  const home = os.homedir();
  const files = [
    `${home}/.fractals-toolbox/shell/zsh/hosts.config.zsh`,
    `${home}/.fractals-toolbox/shell/zsh/hosts.local.zsh`,
    `${home}/.fractals-toolbox-private/personal/hosts.config.zsh`,
    `${home}/.fractals-toolbox/shell/zsh/sshtunnel.config.zsh`,
    `${home}/.fractals-toolbox/shell/zsh/sshtunnel.local.zsh`,
  ];
  const out = new Map();
  for (const f of files) {
    for (const { name, target } of parseToolboxHostText(readIfExists(f))) {
      if (name && target) out.set(name, { name, target, source: 'toolbox' });
    }
  }
  return [...out.values()];
}

function allHosts() {
  const map = new Map();
  for (const h of parseToolboxHosts()) map.set(h.name, h);   // toolbox aliases win
  for (const h of parseSshConfigHosts()) if (!map.has(h.name)) map.set(h.name, h);
  return [...map.values()].sort((a, b) => a.name.localeCompare(b.name));
}

// Resolve a user-supplied token to an ssh target. If it matches a toolbox
// alias, use its target; otherwise pass through (ssh resolves its own config).
function resolveHost(token) {
  const t = parseToolboxHosts().find((h) => h.name === token);
  return t ? t.target : token;
}

// ─────────────────────────────────────────────────────────────────────────
// Local port checks
// ─────────────────────────────────────────────────────────────────────────

function isLocalPortFree(port) {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.once('error', () => resolve(false));
    srv.once('listening', () => srv.close(() => resolve(true)));
    srv.listen(port, '127.0.0.1');
  });
}

async function findFreeLocalPort(preferred) {
  for (let p = preferred; p <= 65535 && p < preferred + 50; p++) {
    if (await isLocalPortFree(p)) return p;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────
// App state
// ─────────────────────────────────────────────────────────────────────────

export const app = {
  host: null,           // resolved ssh target
  display: null,        // friendly name for the header
  sock: null,           // ControlMaster socket path
  ports: [],            // discovered [{port,binds,proc}]
  tunnels: new Map(),   // remotePort -> {localPort, state, error, child}
  selected: 0,
  scroll: 0,
  connected: false,
  lastScan: 0,
  scanning: false,
  tick: 0,
  status: '',           // transient status line
  mode: 'list',         // 'list' | 'input'
  input: null,          // {label, value, onSubmit}
};

const now = () => Date.now();

// ─────────────────────────────────────────────────────────────────────────
// SSH master lifecycle
// ─────────────────────────────────────────────────────────────────────────

function masterSock(host) {
  // Short path under /tmp to stay well under the unix-socket length limit.
  const safe = host.replace(/[^a-zA-Z0-9]/g, '_').slice(0, 24);
  return `/tmp/sshtui.${process.pid}.${safe}.ctl`;
}

// Establish the master connection in the FOREGROUND (before the alt-screen),
// so agent/passphrase/2FA prompts work normally. Returns true on success.
function startMaster(host, sock) {
  const r = spawnSync('ssh', [
    '-M', '-S', sock,
    '-o', 'ControlPersist=30',
    '-o', 'ServerAliveInterval=20',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'ConnectTimeout=15',
    '-N', '-f',
    host,
  ], { stdio: 'inherit' });
  return r.status === 0;
}

function masterAlive(sock, host) {
  const r = spawnSync('ssh', ['-S', sock, '-O', 'check', host],
    { stdio: 'ignore' });
  return r.status === 0;
}

function stopMaster(sock, host) {
  spawnSync('ssh', ['-S', sock, '-O', 'exit', host], { stdio: 'ignore' });
}

// ─────────────────────────────────────────────────────────────────────────
// Discovery
// ─────────────────────────────────────────────────────────────────────────

export function scanPorts() {
  if (app.scanning) return;
  app.scanning = true;
  const chunks = [];
  const child = spawn('ssh', [...clientOpts(app.sock), app.host, REMOTE_SCAN],
    { stdio: ['ignore', 'pipe', 'ignore'] });
  child.stdout.on('data', (d) => chunks.push(d));
  child.on('error', () => { app.scanning = false; });
  child.on('close', (code) => {
    app.scanning = false;
    if (code === 0) {
      app.ports = parsePorts(Buffer.concat(chunks).toString('utf8'));
      app.connected = true;
      app.lastScan = now();
      if (app.selected >= app.ports.length) app.selected = Math.max(0, app.ports.length - 1);
    } else {
      app.connected = masterAlive(app.sock, app.host);
    }
    render();
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Tunnels
//
// Forwards are registered on the ControlMaster with synchronous
// `ssh -O forward` / `-O cancel`. Two hard-won reasons for this shape:
//   1. A fresh `ssh -N -L` spawned from inside the raw-TTY event loop wedges
//      (the child never even initializes) — but commands that ride the
//      already-established master socket work reliably (discovery proves it).
//   2. spawnSync avoids the async child-event delivery that also proved
//      unreliable in the alt-screen runtime. `-O forward` only talks to the
//      local master socket, so it returns in milliseconds.
// The forward lives on the master and is torn down by `-O cancel` or, on quit,
// by `-O exit`. Verified to carry real traffic, including IPv6-loopback ports.
// ─────────────────────────────────────────────────────────────────────────

// Run an `-O` administrative command against the master. Synchronous and fast.
function masterCtl(op, extraArgs = []) {
  return spawnSync('ssh', [
    '-o', 'BatchMode=yes',
    '-o', `ControlPath=${app.sock}`,
    '-o', 'ControlMaster=no',
    '-O', op, ...extraArgs, app.host,
  ], { encoding: 'utf8' });
}

export async function openTunnel(remotePort, desiredLocal) {
  if (app.tunnels.has(remotePort)) return;
  const portInfo = app.ports.find((p) => p.port === remotePort);
  const binds = portInfo ? portInfo.binds : ['0.0.0.0'];

  const wanted = desiredLocal ?? remotePort;
  const free = await isLocalPortFree(wanted);
  const localPort = free ? wanted : await findFreeLocalPort(wanted + 1);
  if (localPort == null) {
    app.status = `No free local port near ${wanted}`;
    render();
    return;
  }

  const spec = forwardSpec(localPort, remotePort, binds);
  const r = masterCtl('forward', ['-L', spec]);
  if (r.status === 0) {
    app.tunnels.set(remotePort, { localPort, spec, state: 'active', error: null });
    if (localPort !== wanted) app.status = `Local ${wanted} busy → using ${localPort}`;
  } else {
    const msg = (r.stderr || '').trim().split('\n').pop() || `ssh -O forward exited ${r.status}`;
    app.tunnels.set(remotePort, { localPort, spec, state: 'error', error: msg });
  }
  render();
}

export function killTunnel(remotePort) {
  const e = app.tunnels.get(remotePort);
  if (!e) return;
  if (e.spec) masterCtl('cancel', ['-L', e.spec]);
  app.tunnels.delete(remotePort);
  render();
}

function killAllTunnels() {
  for (const [, e] of app.tunnels) {
    if (e.spec) masterCtl('cancel', ['-L', e.spec]);
  }
  app.tunnels.clear();
  render();
}

function toggleSelected() {
  const p = app.ports[app.selected];
  if (!p) return;
  if (app.tunnels.has(p.port)) killTunnel(p.port);
  else openTunnel(p.port);
}

// ─────────────────────────────────────────────────────────────────────────
// Rendering (raw ANSI, full-frame repaint)
// ─────────────────────────────────────────────────────────────────────────

const ESC = '\x1b[';
const c = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m', rev: '\x1b[7m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[34m', cyan: '\x1b[36m', gray: '\x1b[90m',
};

function cols() { return process.stdout.columns || 80; }
function rows() { return process.stdout.rows || 24; }

// Fit PLAIN text to exactly `n` visible columns (truncate with … or pad with
// spaces). Color must be applied AROUND the result, never inside, so width math
// stays honest. Strip the line-prefix trap of mixing SGR bytes into widths.
function fit(s, n) {
  s = String(s);
  if (s.length > n) return n <= 1 ? s.slice(0, n) : s.slice(0, n - 1) + '…';
  return s + ' '.repeat(n - s.length);
}
function truncPlain(s, n) {
  s = String(s);
  return s.length <= n ? s : s.slice(0, Math.max(0, n - 1)) + '…';
}

function dot(state) {
  switch (state) {
    case 'active': return `${c.green}●${c.reset}`;
    case 'connecting': return `${c.yellow}${SPINNER[app.tick % SPINNER.length]}${c.reset}`;
    case 'error': return `${c.red}✗${c.reset}`;
    default: return `${c.gray}○${c.reset}`;
  }
}

function render() {
  if (app.mode === 'input') return renderInput();
  const W = cols();
  const H = rows();
  const out = [];

  // Header
  const connBadge = app.connected
    ? `${c.green}⬤ connected${c.reset}`
    : `${c.red}⬤ disconnected${c.reset}`;
  const age = app.lastScan ? `${Math.round((now() - app.lastScan) / 1000)}s ago` : '—';
  const scan = app.scanning ? ` ${c.cyan}${SPINNER[app.tick % SPINNER.length]}${c.reset}` : '';
  const active = [...app.tunnels.values()].filter((t) => t.state === 'active').length;
  out.push(` ${c.bold}${c.cyan}sshtui${c.reset}  ${c.dim}·${c.reset}  ${c.bold}${app.display}${c.reset}` +
    `   ${connBadge}   ${c.dim}⟳ ${age}${scan}${c.reset}   ${c.green}${active} active${c.reset}`);
  out.push(` ${c.dim}${'─'.repeat(Math.max(0, W - 2))}${c.reset}`);

  // Column header. Columns are fixed VISIBLE widths: marker 3, PORT 7,
  // PROCESS 16, BIND 22, then TUNNEL. Row layout below must match exactly.
  out.push(`${c.dim}   ${fit('PORT', 7)}${fit('PROCESS', 16)}${fit('BIND', 22)}TUNNEL${c.reset}`);

  // Body viewport
  const headerLines = 3;
  const footerLines = 3;
  const viewH = Math.max(1, H - headerLines - footerLines);

  if (app.ports.length === 0) {
    out.push('');
    out.push(app.connected
      ? `   ${c.dim}No listening TCP ports found.${c.reset}`
      : `   ${c.yellow}Waiting for first scan…${c.reset}`);
    while (out.length < headerLines + viewH) out.push('');
  } else {
    // keep selection in view
    if (app.selected < app.scroll) app.scroll = app.selected;
    if (app.selected >= app.scroll + viewH) app.scroll = app.selected - viewH + 1;

    for (let i = 0; i < viewH; i++) {
      const idx = app.scroll + i;
      if (idx >= app.ports.length) { out.push(''); continue; }
      const p = app.ports[idx];
      const tun = app.tunnels.get(p.port);
      const state = tun ? tun.state : 'idle';
      const sel = idx === app.selected;

      let tunnelCol;
      if (!tun) tunnelCol = `${c.dim}↵ to tunnel${c.reset}`;
      else if (tun.state === 'connecting') tunnelCol = `${c.yellow}→ :${tun.localPort} connecting${c.reset}`;
      else if (tun.state === 'active') tunnelCol = `${c.green}→ localhost:${tun.localPort}${c.reset}`;
      else tunnelCol = `${c.red}error: ${truncPlain(tun.error || '', Math.max(8, W - 50))}${c.reset}`;

      const left =
        ` ${dot(state)} ` +                                                  // marker: 3 cols
        `${c.bold}${fit(String(p.port), 7)}${c.reset}` +                      // PORT: 7
        (p.proc ? fit(p.proc, 16) : `${c.gray}${fit('—', 16)}${c.reset}`) +   // PROCESS: 16
        `${c.dim}${fit(truncPlain(bindSummary(p.binds), 21), 22)}${c.reset}`; // BIND: 22 (≥1 gutter)

      let line = left + tunnelCol;
      if (sel) {
        const plain = line.replace(/\x1b\[[0-9;]*m/g, '');
        line = `${c.rev}${fit(plain, W - 1)}${c.reset}`;
      }
      out.push(line);
    }
  }

  // Footer
  out.push(` ${c.dim}${'─'.repeat(Math.max(0, W - 2))}${c.reset}`);
  if (app.status) {
    out.push(` ${c.yellow}${truncPlain(app.status, W - 3)}${c.reset}`);
  } else {
    out.push(` ${c.dim}↑/↓${c.reset} move  ${c.dim}↵${c.reset} tunnel/kill  ` +
      `${c.dim}c${c.reset} custom port  ${c.dim}a${c.reset} add port  ` +
      `${c.dim}r${c.reset} refresh  ${c.dim}K${c.reset} kill all  ${c.dim}q${c.reset} quit`);
  }

  paint(out, H);
}

function renderInput() {
  const W = cols();
  const H = rows();
  const out = [];
  out.push(` ${c.bold}${c.cyan}sshtui${c.reset}  ${c.dim}·${c.reset}  ${c.bold}${app.display}${c.reset}`);
  out.push(` ${c.dim}${'─'.repeat(Math.max(0, W - 2))}${c.reset}`);
  while (out.length < H - 4) out.push('');
  out.push(` ${c.bold}${app.input.label}${c.reset}`);
  out.push(` ${c.cyan}❯${c.reset} ${app.input.value}${c.rev} ${c.reset}`);
  out.push(` ${c.dim}↵ confirm   esc cancel${c.reset}`);
  paint(out, H);
}

function paint(lines, H) {
  let frame = `${ESC}H`; // cursor home
  for (let i = 0; i < H; i++) {
    frame += (lines[i] ?? '') + `${ESC}K`; // clear to EOL
    if (i < H - 1) frame += '\r\n';
  }
  frame += `${ESC}J`; // clear below
  process.stdout.write(frame);
}

// ─────────────────────────────────────────────────────────────────────────
// Input handling
// ─────────────────────────────────────────────────────────────────────────

function promptInput(label, initial, onSubmit) {
  app.mode = 'input';
  app.input = { label, value: String(initial ?? ''), onSubmit };
  render();
}

function handleInputKey(s) {
  if (s === '\x1b') { app.mode = 'list'; app.input = null; render(); return; }
  if (s === '\r' || s === '\n') {
    const { value, onSubmit } = app.input;
    app.mode = 'list'; app.input = null;
    onSubmit(value.trim());
    render();
    return;
  }
  if (s === '\x7f' || s === '\b') { app.input.value = app.input.value.slice(0, -1); render(); return; }
  if (/^[0-9]$/.test(s)) { app.input.value += s; render(); }
}

function handleListKey(s) {
  app.status = '';
  switch (s) {
    case '\x03': case 'q': quit(); return;        // Ctrl-C / q
    case '\x1b[A': case 'k':                        // up
      if (app.selected > 0) app.selected--; break;
    case '\x1b[B': case 'j':                        // down
      if (app.selected < app.ports.length - 1) app.selected++; break;
    case '\x1b[H': case 'g': app.selected = 0; break;
    case '\x1b[F': case 'G': app.selected = Math.max(0, app.ports.length - 1); break;
    case '\r': case '\n': case ' ': toggleSelected(); return;
    case 'r': scanPorts(); break;
    case 'K': killAllTunnels(); return;
    case 'c': {
      const p = app.ports[app.selected];
      if (p) promptInput(`Local port for remote ${p.port}:`, p.port,
        (v) => { const n = Number.parseInt(v, 10); if (n > 0 && n <= 65535) openTunnel(p.port, n); });
      return;
    }
    case 'a':
      promptInput('Tunnel an arbitrary remote port:', '',
        (v) => { const n = Number.parseInt(v, 10); if (n > 0 && n <= 65535) openTunnel(n); });
      return;
    default: return;
  }
  render();
}

// Split a raw input chunk into individual keys. A single read can contain
// several keystrokes (paste, fast typing, or a driver like expect sending
// "4000\r" at once); without this, multi-byte chunks fall through every
// single-char case and get silently dropped. Escape sequences (arrows etc.)
// are kept whole as one key.
export function keysFromBuffer(s) {
  const keys = [];
  for (let i = 0; i < s.length;) {
    if (s[i] === '\x1b' && (s[i + 1] === '[' || s[i + 1] === 'O')) {
      let j = i + 2;
      while (j < s.length && !/[A-Za-z~]/.test(s[j])) j++;
      keys.push(s.slice(i, j + 1));
      i = j + 1;
    } else {
      keys.push(s[i]);
      i++;
    }
  }
  return keys;
}

function onKey(buf) {
  // Re-check mode per key: 'a'/'c' switch to input mode mid-chunk.
  for (const k of keysFromBuffer(buf.toString('utf8'))) {
    if (app.mode === 'input') handleInputKey(k);
    else handleListKey(k);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Terminal setup / teardown
// ─────────────────────────────────────────────────────────────────────────

let cleanedUp = false;
function enterTui() {
  process.stdout.write(`${ESC}?1049h${ESC}?25l`); // alt screen + hide cursor
  if (process.stdin.isTTY) process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on('data', onKey);
}

function restoreTerminal() {
  if (process.stdin.isTTY) { try { process.stdin.setRawMode(false); } catch {} }
  process.stdout.write(`${ESC}?25h${ESC}?1049l`); // show cursor + leave alt screen
}

function quit(code = 0) {
  if (cleanedUp) return;
  cleanedUp = true;
  killAllTunnels();                              // SIGTERM each dedicated tunnel child
  if (app.sock) stopMaster(app.sock, app.host);  // tear down the discovery master
  restoreTerminal();
  process.exit(code);
}

// ─────────────────────────────────────────────────────────────────────────
// Host picker (no-arg startup)
// ─────────────────────────────────────────────────────────────────────────

function pickHost() {
  return new Promise((resolve) => {
    const hosts = allHosts();
    if (hosts.length === 0) {
      restoreTerminal();
      console.error('No hosts found in ~/.ssh/config or toolbox aliases.');
      console.error('Usage: sshtui <host-or-alias>');
      process.exit(1);
    }
    let sel = 0;
    const draw = () => {
      const H = rows();
      const out = [` ${c.bold}${c.cyan}sshtui${c.reset}  ${c.dim}· choose a host${c.reset}`,
        ` ${c.dim}${'─'.repeat(Math.max(0, cols() - 2))}${c.reset}`];
      hosts.forEach((h, i) => {
        const label = ` ${h.name}  ${c.dim}${h.target !== h.name ? '→ ' + h.target : ''} (${h.source})${c.reset}`;
        out.push(i === sel ? `${c.rev}${fit(label.replace(/\x1b\[[0-9;]*m/g, ''), cols() - 1)}${c.reset}` : label);
      });
      out.push('');
      out.push(` ${c.dim}↑/↓ move   ↵ select   q quit${c.reset}`);
      paint(out, H);
    };
    const onPick = (buf) => {
      for (const s of keysFromBuffer(buf.toString('utf8'))) {
        if (s === '\x03' || s === 'q') { process.stdin.off('data', onPick); quit(); }
        else if (s === '\x1b[A' || s === 'k') { if (sel > 0) sel--; draw(); }
        else if (s === '\x1b[B' || s === 'j') { if (sel < hosts.length - 1) sel++; draw(); }
        else if (s === '\r' || s === '\n') { process.stdin.off('data', onPick); resolve(hosts[sel]); return; }
      }
    };
    process.stdin.on('data', onPick);
    draw();
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────

async function main() {
  const arg = process.argv[2];

  if (arg === '-h' || arg === '--help') {
    console.log(`sshtui — interactive SSH port-tunnel TUI

Usage:
  sshtui [host-or-alias]

  With no argument, pick a host from ~/.ssh/config + toolbox aliases.
  Inside: ↑/↓ move · ↵ tunnel/kill · c custom local port · a arbitrary
  remote port · r refresh · K kill all · q quit.`);
    process.exit(0);
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error('sshtui needs an interactive terminal.');
    process.exit(1);
  }

  for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => quit());
  process.on('uncaughtException', (e) => { restoreTerminal(); console.error(e); quit(1); });

  enterTui();

  let chosen;
  if (arg) {
    chosen = { name: arg, target: resolveHost(arg), source: 'arg' };
  } else {
    chosen = await pickHost();
  }

  app.host = chosen.target;
  app.display = chosen.name === chosen.target ? chosen.name : `${chosen.name} (${chosen.target})`;
  app.sock = masterSock(app.host);

  // Establish the master with the terminal temporarily restored so any
  // passphrase/agent/2FA prompt is visible and interactive.
  restoreTerminal();
  process.stdout.write(`Connecting to ${app.host} …\n`);
  process.stdin.removeListener('data', onKey);
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  const ok = startMaster(app.host, app.sock);
  if (!ok) {
    console.error(`\nFailed to connect to ${app.host}.`);
    process.exit(1);
  }
  app.connected = true;

  // Re-enter the TUI for the main loop.
  enterTui();
  render();
  scanPorts();

  setInterval(() => {
    app.tick++;
    if (now() - app.lastScan >= REFRESH_MS) scanPorts();
    render();
  }, REPAINT_MS);

  process.stdout.on('resize', render);
}

// Only run when executed directly (not when imported by tests).
if (process.argv[1] && fileURLToPath(import.meta.url) === fs.realpathSync(process.argv[1])) {
  main();
}
