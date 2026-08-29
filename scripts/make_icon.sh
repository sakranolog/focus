#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

IN="${1:-}"
mkdir -p build packaging
if [ -n "$IN" ]; then
  swift scripts/IconTool.swift build/icon_1024.png "$IN"
else
  swift scripts/IconTool.swift build/icon_1024.png
fi

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
  d=$((s * 2))
  sips -z $d $d build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o packaging/AppIcon.icns
echo "wrote packaging/AppIcon.icns"
