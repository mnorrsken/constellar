#!/bin/sh
# Builds the macOS disk image from Godot's zipped export (make export-mac).
# Run on macOS (hdiutil):
#
#   packaging/macos/build-dmg.sh build/macos/Constellar.zip 0.1.0 dist
#
# The image holds Constellar.app and a link to /Applications to drag it onto.
# Godot names the bundle after the project ("Constellar- Merchant Empire.app");
# it is renamed here, which leaves its ad-hoc signature valid.
set -eu

zip=$1
version=${2#v}
out=${3:-dist}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/root"
ditto -x -k "$zip" "$work/root"

app=$(find "$work/root" -maxdepth 1 -name '*.app' | head -n 1)
[ -n "$app" ] || { echo "no .app in $zip" >&2; exit 1; }
[ "$app" = "$work/root/Constellar.app" ] || mv "$app" "$work/root/Constellar.app"
codesign --verify --deep --strict "$work/root/Constellar.app"
ln -s /Applications "$work/root/Applications"

mkdir -p "$out"
dmg="$out/constellar_${version}_macos_universal.dmg"
hdiutil create -volname "Constellar" -srcfolder "$work/root" -fs HFS+ -format UDZO -ov "$dmg"
hdiutil verify "$dmg"
echo "Built $dmg"
