#!/usr/bin/env bash
set -euo pipefail

ZSHRC_PATH="${ZSHRC_PATH:-$HOME/.zshrc}"

if command -v python3 >/dev/null 2>&1; then
  ZSHRC_PATH="$ZSHRC_PATH" python3 - <<'PY'
import os
from pathlib import Path

zshrc_path = Path(os.environ["ZSHRC_PATH"]).expanduser()
if not zshrc_path.exists():
    raise SystemExit(f"Missing {zshrc_path}")

text = zshrc_path.read_text()

plugins_marker = ">>> fractals-toolbox plugins"
zshrc_marker = ">>> fractals-toolbox zshrc"

plugins_block = """# >>> fractals-toolbox plugins
if [[ -r \"$HOME/.fractals-toolbox/zsh/omz-plugins.zsh\" ]]; then
  source \"$HOME/.fractals-toolbox/zsh/omz-plugins.zsh\"
fi
# <<< fractals-toolbox plugins
"""

zshrc_block = """# >>> fractals-toolbox zshrc
if [[ -r \"$HOME/.fractals-toolbox/zsh/zshrc\" ]]; then
  source \"$HOME/.fractals-toolbox/zsh/zshrc\"
fi
# <<< fractals-toolbox zshrc
"""

updated = False

if plugins_marker not in text:
    lines = text.splitlines(keepends=True)
    insert_at = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith("plugins=("):
            if line.strip().endswith(")"):
                insert_at = i + 1
            else:
                end = None
                for j in range(i + 1, len(lines)):
                    if lines[j].strip() == ")":
                        end = j
                        break
                if end is not None:
                    insert_at = end + 1
            break

    if insert_at is not None:
        lines.insert(insert_at, plugins_block + "\n")
        text = "".join(lines)
        updated = True

if zshrc_marker not in text:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + zshrc_block + "\n"
    updated = True

if updated:
    zshrc_path.write_text(text)
PY
else
  printf 'python3 not found; skipping zshrc edits\n' >&2
fi
