#!/usr/bin/env node
// Unit tests for the pure parsing/targeting helpers. Run: node test-parse.mjs
import {
  extractPort, extractBind, parsePorts, forwardTarget, forwardSpec, bindSummary,
  keysFromBuffer, parseToolboxHostText,
} from './sshtui.mjs';

let pass = 0, fail = 0;
function eq(actual, expected, name) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) { pass++; }
  else { fail++; console.error(`FAIL ${name}\n  expected ${e}\n  got      ${a}`); }
}

// ── extractPort / extractBind across real-world address shapes ──
eq(extractPort('0.0.0.0:22'), 22, 'port v4 wildcard');
eq(extractPort('127.0.0.1:5432'), 5432, 'port v4 loopback');
eq(extractPort('*:9993'), 9993, 'port star');
eq(extractPort('127.0.0.53%lo:53'), 53, 'port with zone suffix');
eq(extractPort('[::1]:4000'), 4000, 'port v6 loopback');
eq(extractPort('[::]:5355'), 5355, 'port v6 wildcard');
eq(extractPort('[fd7a:115c:a1e0::f739:237e]:44119'), 44119, 'port v6 global');
eq(extractPort('garbage'), null, 'port none');

eq(extractBind('0.0.0.0:22'), '0.0.0.0', 'bind v4 wildcard');
eq(extractBind('127.0.0.53%lo:53'), '127.0.0.53', 'bind strips zone');
eq(extractBind('[::1]:4000'), '::1', 'bind strips v6 brackets');
eq(extractBind('[fd7a:115c:a1e0::f739:237e]:44119'), 'fd7a:115c:a1e0::f739:237e', 'bind v6 global');
eq(extractBind('*:9993'), '*', 'bind star');

// ── parsePorts on the EXACT ss -tlnpH output captured from unixboat ──
const ssReal = `LISTEN 0      4096                 127.0.0.53%lo:53    0.0.0.0:*
LISTEN 0      5                        127.0.0.1:5335  0.0.0.0:*
LISTEN 0      4096                     127.0.0.1:11434 0.0.0.0:*
LISTEN 0      4096                    127.0.0.54:53    0.0.0.0:*
LISTEN 0      128                      127.0.0.1:24289 0.0.0.0:* users:(("serena",pid=2286496,fd=8))
LISTEN 0      4096                       0.0.0.0:9993  0.0.0.0:*
LISTEN 0      32                   192.168.122.1:53    0.0.0.0:*
LISTEN 0      128                        0.0.0.0:22    0.0.0.0:*
LISTEN 0      5                                *:9993        *:*
LISTEN 0      4096                          [::]:5355     [::]:*
LISTEN 0      511                          [::1]:4000     [::]:* users:(("MainThread",pid=2467044,fd=21))
LISTEN 0      128                           [::]:22       [::]:*`;

const ports = parsePorts(ssReal);
const byPort = Object.fromEntries(ports.map((p) => [p.port, p]));

eq(ports.map((p) => p.port), [22, 53, 4000, 5335, 5355, 9993, 11434, 24289], 'deduped sorted ports');
eq(byPort[53].binds.sort(), ['127.0.0.53', '127.0.0.54', '192.168.122.1'], 'port 53 three binds deduped');
eq(byPort[22].binds.sort(), ['0.0.0.0', '::'], 'port 22 dual-stack');
eq(byPort[9993].binds.sort(), ['*', '0.0.0.0'], 'port 9993 star+wildcard');
eq(byPort[24289].proc, 'serena', 'proc name parsed');
eq(byPort[4000].proc, 'MainThread', 'v6-only proc name parsed');
eq(byPort[4000].binds, ['::1'], 'port 4000 v6 loopback only');

// ── netstat fallback format ──
const netstat = `tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      1234/node
tcp6       0      0 :::3000                 :::*                    LISTEN      5678/python3`;
const np = parsePorts(netstat);
eq(np.map((p) => p.port), [3000, 8080], 'netstat ports');
eq(np.find((p) => p.port === 8080).proc, 'node', 'netstat proc v4');
eq(np.find((p) => p.port === 3000).proc, 'python3', 'netstat proc v6');

// ── forwardTarget: the load-bearing IPv6-loopback fix ──
eq(forwardTarget(['0.0.0.0', '::']), '127.0.0.1', 'dual-stack → v4 loopback');
eq(forwardTarget(['::1']), '::1', 'v6-loopback-only → ::1 (NOT 127.0.0.1)');
eq(forwardTarget(['::']), '::1', 'v6 wildcard → ::1');
eq(forwardTarget(['127.0.0.1']), '127.0.0.1', 'v4 loopback');
eq(forwardTarget(['192.168.122.1']), '192.168.122.1', 'specific v4 iface');
eq(forwardTarget(['*']), '127.0.0.1', 'star → v4 loopback');

// ── forwardSpec: bracketing ──
eq(forwardSpec(4000, 4000, ['::1']), '127.0.0.1:4000:[::1]:4000', 'v6 target bracketed');
eq(forwardSpec(8080, 80, ['0.0.0.0']), '127.0.0.1:8080:127.0.0.1:80', 'v4 remap spec');

// ── bindSummary ──
eq(bindSummary(['0.0.0.0']), '0.0.0.0', 'summary single');
eq(bindSummary(['0.0.0.0', '::']), '0.0.0.0 +1', 'summary multi');

// ── toolbox host aliases: current array style + older indexed style ──
const toolboxHosts = parseToolboxHostText(`typeset -gA FRACTAL_HOST_ALIASES
FRACTAL_HOST_ALIASES=(
  saturn-02 root@saturn-02
  unixboat benjude@unixboat
  quoted "ben jude@example.com" # comment
)
SSHTUNNEL_HOSTS[legacy]=root@legacy
`);
eq(toolboxHosts, [
  { name: 'saturn-02', target: 'root@saturn-02' },
  { name: 'unixboat', target: 'benjude@unixboat' },
  { name: 'quoted', target: 'ben jude@example.com' },
  { name: 'legacy', target: 'root@legacy' },
], 'toolbox host aliases parse');

// ── keysFromBuffer: batched input must split into individual keys ──
eq(keysFromBuffer('4000\r'), ['4', '0', '0', '0', '\r'], 'batched digits+enter split');
eq(keysFromBuffer('\x1b[A'), ['\x1b[A'], 'arrow up kept whole');
eq(keysFromBuffer('j\x1b[Bk'), ['j', '\x1b[B', 'k'], 'mixed keys + escape seq');
eq(keysFromBuffer('\x1b[A\x1b[B'), ['\x1b[A', '\x1b[B'], 'two escape seqs');
eq(keysFromBuffer('\x7f'), ['\x7f'], 'backspace');
eq(keysFromBuffer('\x1b'), ['\x1b'], 'lone escape');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
