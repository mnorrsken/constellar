#!/usr/bin/env bash
# The project's "verify before done" checks (CLAUDE.md), for CI: a clean
# headless import (its exit code proves nothing, so the log is grepped), the
# test suite, and a short headless run of the game. Uses $GODOT_BIN (set by
# the setup-godot action), else `godot` on PATH.
set -euo pipefail

godot="${GODOT_BIN:-godot}"
logs=$(mktemp -d)

# A fresh checkout has no .godot cache, and its first import loads the UI
# theme before the fonts are imported, logging errors a second pass doesn't.
make import GODOT="$godot" > "$logs/first-import.log" 2>&1 || true

make import GODOT="$godot" 2>&1 | tee "$logs/import.log"
if grep -E "ERROR|SCRIPT|WARNING" "$logs/import.log"; then
  echo "::error::make import reported problems (above)"
  exit 1
fi

make test GODOT="$godot"

"$godot" --headless --quit-after 20 --path . 2>&1 | tee "$logs/run.log"
if grep -iE "error|warning" "$logs/run.log"; then
  echo "::error::the headless run reported problems (above)"
  exit 1
fi
