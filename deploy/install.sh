#!/usr/bin/env bash
# fractals-toolbox installer.
#
# Detects OS+shell on the current machine, applies the appropriate wiring:
#   - tmux:  symlink ~/.tmux.conf  → common/tmux/tmux.conf            (always)
#   - zsh:   ~/.zshrc marker blocks (plugins + zshrc), prune dead inline autospawn
#   - fish:  symlink shell/fish/fractals-toolbox.fish → ~/.config/fish/conf.d/
#
# Each branch is independent and idempotent. Re-running on a healthy machine
# is a no-op aside from log lines.
set -euo pipefail

TOOLBOX="$HOME/.fractals-toolbox"
ZSHRC="${ZSHRC_PATH:-$HOME/.zshrc}"
TMUX_LINK="$HOME/.tmux.conf"
TMUX_TARGET="$TOOLBOX/common/tmux/tmux.conf"
FISH_CONFD="$HOME/.config/fish/conf.d"
FISH_LINK="$FISH_CONFD/fractals-toolbox.fish"
FISH_TARGET="$TOOLBOX/shell/fish/fractals-toolbox.fish"

log() { printf 'install: %s\n' "$*"; }
fail() { printf 'install: error: %s\n' "$*" >&2; exit 1; }

[[ -d "$TOOLBOX" ]] || fail "$TOOLBOX not found — clone the repo to ~/.fractals-toolbox first"
[[ -f "$TMUX_TARGET" ]] || fail "$TMUX_TARGET missing — repo looks incomplete"
[[ -f "$FISH_TARGET" ]] || fail "$FISH_TARGET missing — repo looks incomplete"

ts() { date +%Y%m%d%H%M%S; }

# ----------------------------------------------------------------------------
# tmux: symlink ~/.tmux.conf → common/tmux/tmux.conf
# ----------------------------------------------------------------------------
install_tmux_conf() {
  if [[ -L "$TMUX_LINK" ]] && [[ "$(readlink "$TMUX_LINK")" == "$TMUX_TARGET" ]]; then
    log "tmux: $TMUX_LINK already symlinked → $TMUX_TARGET"
    return 0
  fi

  if [[ -L "$TMUX_LINK" ]]; then
    local prev_target
    prev_target="$(readlink "$TMUX_LINK")"
    log "tmux: $TMUX_LINK was symlinked to $prev_target — replacing"
    rm "$TMUX_LINK"
  elif [[ -e "$TMUX_LINK" ]]; then
    local backup="$TMUX_LINK.pre-fractals.$(ts).bak"
    log "tmux: backing up existing $TMUX_LINK → $backup"
    mv "$TMUX_LINK" "$backup"
  fi

  ln -s "$TMUX_TARGET" "$TMUX_LINK"
  log "tmux: $TMUX_LINK → $TMUX_TARGET"
}

# ----------------------------------------------------------------------------
# zsh: ~/.zshrc marker blocks + prune dead inline autospawn
# ----------------------------------------------------------------------------
install_zsh() {
  if [[ ! -e "$ZSHRC" ]]; then
    log "zsh: no $ZSHRC — skipping"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 required for zshrc edits"

  ZSHRC_PATH="$ZSHRC" python3 - <<'PY'
import os, re, sys
from pathlib import Path

zshrc_path = Path(os.environ["ZSHRC_PATH"]).expanduser()
original = zshrc_path.read_text()
text = original

PLUGINS_BLOCK = """# >>> fractals-toolbox plugins
if [[ -r "$HOME/.fractals-toolbox/shell/zsh/omz-plugins.zsh" ]]; then
  source "$HOME/.fractals-toolbox/shell/zsh/omz-plugins.zsh"
fi
# <<< fractals-toolbox plugins
"""

ZSHRC_BLOCK = """# >>> fractals-toolbox zshrc
if [[ -r "$HOME/.fractals-toolbox/shell/zsh/zshrc" ]]; then
  source "$HOME/.fractals-toolbox/shell/zsh/zshrc"
fi
# <<< fractals-toolbox zshrc
"""

def replace_marker_block(text, name, block):
    """Replace the >>> name ... <<< name block with `block`. Returns (new_text, replaced?)."""
    pattern = re.compile(
        r"# >>> " + re.escape(name) + r"\b.*?# <<< " + re.escape(name) + r"[^\n]*\n",
        re.DOTALL,
    )
    if pattern.search(text):
        return pattern.sub(block, text, count=1), True
    return text, False

def find_plugins_array_end(text):
    """Return the byte offset just past the closing ) of a top-level `plugins=(...)` array,
    or None if not found. Handles single-line and multi-line forms."""
    m = re.search(r"^plugins=\(", text, re.MULTILINE)
    if not m:
        return None
    start = m.end()
    # Walk forward to find matching `)` — plugins arrays don't nest, so first `)` wins.
    close = text.find(")", start)
    if close == -1:
        return None
    # Include the trailing newline if present.
    nl = text.find("\n", close)
    return (nl + 1) if nl != -1 else len(text)

# 1. Plugins block: replace if present, else insert after plugins=(...) array.
text, plugins_replaced = replace_marker_block(text, "fractals-toolbox plugins", PLUGINS_BLOCK)
if not plugins_replaced:
    insert_at = find_plugins_array_end(text)
    if insert_at is not None:
        text = text[:insert_at] + "\n" + PLUGINS_BLOCK + text[insert_at:]
    # If no plugins=(...) array, this user probably isn't using oh-my-zsh — skip silently.

# 2. Zshrc block: replace if present, else append at end.
text, zshrc_replaced = replace_marker_block(text, "fractals-toolbox zshrc", ZSHRC_BLOCK)
if not zshrc_replaced:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + ZSHRC_BLOCK

# 3. Remove dead inline autospawn block — toolbox now owns this.
#    Anchored to the verbatim form. If the user has customized, the regex misses
#    (both copies coexist; toolbox wins via exec — still safe).
INLINE_AUTOSPAWN = re.compile(
    r"\n*# Auto-spawn a fresh tmux session per interactive terminal window\.\n"
    r"if \[\[ -z \"\$TMUX\" \]\] && \[\[ \$- == \*i\* \]\] && \[\[ -n \"\$PS1\" \]\] && command -v tmux >/dev/null 2>&1; then\n"
    r"  exec tmux new -s \"term-\$\$\"\n"
    r"fi\n*"
)
text = INLINE_AUTOSPAWN.sub("\n", text, count=1)

# Normalize: collapse 3+ trailing newlines to 1.
text = re.sub(r"\n{3,}\Z", "\n", text)

if text == original:
    print("zsh: no changes needed")
    sys.exit(0)

# Backup once before writing.
ts = __import__("time").strftime("%Y%m%d%H%M%S")
backup = zshrc_path.with_suffix(zshrc_path.suffix + f".pre-fractals.{ts}.bak")
backup.write_text(original)
print(f"zsh: backup {backup}")

# Atomic write.
tmp = zshrc_path.with_suffix(zshrc_path.suffix + f".tmp.{os.getpid()}")
tmp.write_text(text)
os.replace(tmp, zshrc_path)

changes = []
if plugins_replaced: changes.append("plugins block updated")
elif "fractals-toolbox plugins" in text: changes.append("plugins block inserted")
if zshrc_replaced: changes.append("zshrc block updated")
elif "fractals-toolbox zshrc" in text: changes.append("zshrc block inserted")
if "Auto-spawn a fresh tmux session" not in text and "Auto-spawn a fresh tmux session" in original:
    changes.append("inline autospawn removed")
print("zsh: " + ", ".join(changes) if changes else "zsh: written")
PY
}

# ----------------------------------------------------------------------------
# fish: symlink shell/fish/fractals-toolbox.fish → ~/.config/fish/conf.d/
# ----------------------------------------------------------------------------
install_fish() {
  if ! command -v fish >/dev/null 2>&1; then
    log "fish: not installed — skipping"
    return 0
  fi

  if [[ -L "$FISH_LINK" ]] && [[ "$(readlink "$FISH_LINK")" == "$FISH_TARGET" ]]; then
    log "fish: $FISH_LINK already symlinked → $FISH_TARGET"
    return 0
  fi

  mkdir -p "$FISH_CONFD"

  if [[ -L "$FISH_LINK" ]]; then
    local prev_target
    prev_target="$(readlink "$FISH_LINK")"
    log "fish: $FISH_LINK was symlinked to $prev_target — replacing"
    rm "$FISH_LINK"
  elif [[ -e "$FISH_LINK" ]]; then
    local backup="$FISH_LINK.pre-fractals.$(ts).bak"
    log "fish: backing up existing $FISH_LINK → $backup"
    mv "$FISH_LINK" "$backup"
  fi

  ln -s "$FISH_TARGET" "$FISH_LINK"
  log "fish: $FISH_LINK → $FISH_TARGET"
}

# ----------------------------------------------------------------------------
# Run all branches.
# ----------------------------------------------------------------------------
log "OS: $(uname -s)  toolbox: $TOOLBOX"
install_tmux_conf
install_zsh
install_fish
log "done"
