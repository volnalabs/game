#!/usr/bin/env bash
# Builds the TerraFront release archives into build/release/:
#   TerraFront-windows-x64.zip     (TerraFront.exe + LICENSE.txt + README.txt)
#   TerraFront-linux-x64.tar.gz    (TerraFront.x86_64 + LICENSE.txt + README.txt)
# Needs Godot (tools/get_godot.sh) and its export templates (tools/get_templates.py).
# Usage (repo root): tools/release/package.sh [version]
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="${1:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' godot/project.godot)}"
GODOT="${GODOT:-$(tools/get_godot.sh)}"
python3 tools/get_templates.py > /dev/null
OUT=build/release
rm -rf "$OUT" build/windows build/linux
mkdir -p "$OUT" build/windows build/linux
"$GODOT" --headless --path godot --import > /dev/null 2>&1 || true
"$GODOT" --headless --path godot --export-release "Windows" ../build/windows/TerraFront.exe > build/export_windows.log 2>&1
"$GODOT" --headless --path godot --export-release "Linux" ../build/linux/TerraFront.x86_64 > build/export_linux.log 2>&1
test -s build/windows/TerraFront.exe
test -s build/linux/TerraFront.x86_64

readme() {
	cat <<TXT
TerraFront ${VERSION} — стратегия захвата территорий от VolnaLabs / territory strategy by VolnaLabs

Запуск / How to run
  Windows: TerraFront.exe   (SmartScreen может предупредить о неподписанном файле: «Подробнее» → «Выполнить в любом случае»)
  Linux:   ./TerraFront.x86_64
Сохранения и настройки / Saves and settings:
  Windows: %APPDATA%\\Godot\\app_userdata\\TerraFront\\
  Linux:   ~/.local/share/godot/app_userdata/TerraFront/

© OpenFront and Contributors · основано на RoWorld (© 2026 Snick Co.) · TerraFront © VolnaLabs
Лицензия / Licence: GNU AGPL v3 с дополнительными условиями §7 — LICENSE.txt.
Исходный код этой версии / Source code of this version:
  https://github.com/volnalabs/game/tree/v${VERSION}
Godot Engine — MIT License (полный текст — в игре, «Титры и лицензии» / in game, Credits).
TXT
}

stage=$(mktemp -d)
mkdir -p "$stage/TerraFront"
cp build/windows/TerraFront.exe "$stage/TerraFront/"
cp LICENSE "$stage/TerraFront/LICENSE.txt"
readme > "$stage/TerraFront/README.txt"
(cd "$stage" && zip -qr9 TerraFront-windows-x64.zip TerraFront)
mv "$stage/TerraFront-windows-x64.zip" "$OUT/"
rm -rf "$stage/TerraFront"
mkdir -p "$stage/TerraFront"
cp build/linux/TerraFront.x86_64 "$stage/TerraFront/"
chmod +x "$stage/TerraFront/TerraFront.x86_64"
cp LICENSE "$stage/TerraFront/LICENSE.txt"
readme > "$stage/TerraFront/README.txt"
tar -C "$stage" -czf "$OUT/TerraFront-linux-x64.tar.gz" TerraFront
rm -rf "$stage"
(cd "$OUT" && sha256sum TerraFront-windows-x64.zip TerraFront-linux-x64.tar.gz > SHA256SUMS.txt)
ls -la "$OUT"
