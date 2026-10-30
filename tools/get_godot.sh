#!/usr/bin/env bash
# Downloads the pinned Godot 4 editor binary (MIT licensed, https://godotengine.org/license)
# into ~/.local/godot and prints its path. Used by local scripts and CI.
#   tools/get_godot.sh            -> prints the binary path
#   GODOT_VERSION=4.7.2 tools/get_godot.sh
set -euo pipefail
VERSION="${GODOT_VERSION:-4.7.2}"
DEST="${GODOT_HOME:-$HOME/.local/godot}"
BIN="$DEST/Godot_v${VERSION}-stable_linux.x86_64"
if [[ ! -x "$BIN" ]]; then
	mkdir -p "$DEST"
	URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip"
	TMP="$(mktemp -d)"
	curl -sSL --retry 4 -o "$TMP/godot.zip" "$URL"
	unzip -q -o "$TMP/godot.zip" -d "$DEST"
	rm -rf "$TMP"
	chmod +x "$BIN"
fi
echo "$BIN"
