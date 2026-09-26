#!/usr/bin/env bash
# Installs Godot $GODOT_VERSION (Linux x86_64) as /usr/local/bin/godot and,
# with --templates, the Windows and macOS export templates (the rest of the
# 1.3 GB bundle is dropped, which keeps the actions/cache entry small).
set -euo pipefail

v="${GODOT_VERSION:?set GODOT_VERSION, e.g. 4.7.2}"
base="https://github.com/godotengine/godot/releases/download/${v}-stable"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/godot.zip" "$base/Godot_v${v}-stable_linux.x86_64.zip"
unzip -q "$tmp/godot.zip" -d "$tmp"
sudo install -m 755 "$tmp/Godot_v${v}-stable_linux.x86_64" /usr/local/bin/godot
godot --version

if [ "${1:-}" = "--templates" ]; then
  dir="$HOME/.local/share/godot/export_templates/${v}.stable"
  if [ -f "$dir/version.txt" ]; then
    echo "Export templates already in $dir (cache)"
  else
    curl -fsSL -o "$tmp/templates.tpz" "$base/Godot_v${v}-stable_export_templates.tpz"
    mkdir -p "$dir"
    unzip -q -j "$tmp/templates.tpz" 'templates/version.txt' 'templates/windows_*_x86_64*' \
      'templates/macos.zip' -d "$dir"
  fi
  ls -la "$dir"
fi
