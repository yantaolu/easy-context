#!/bin/bash
# 由 1024×1024 母版 PNG 生成 AppIcon.appiconset 的全部尺寸。
# 用法：scripts/make-app-icon.sh [母版 PNG]（默认 design/AppIcon.png）
# 母版要求：1024×1024、透明背景、图标主体占约 824×824（macOS 图标网格）。
set -euo pipefail
cd "$(dirname "$0")/.."
src="${1:-design/AppIcon.png}"
out="EasyContext/Assets.xcassets/AppIcon.appiconset"
w=$(sips -g pixelWidth "$src" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$src" | awk '/pixelHeight/ {print $2}')
if [ "$w" != 1024 ] || [ "$h" != 1024 ]; then
    echo "母版必须是 1024×1024，当前为 ${w}×${h}：$src" >&2
    exit 1
fi
for size in 16 32 64 128 256 512 1024; do
    sips -s format png -z "$size" "$size" "$src" --out "$out/icon_${size}.png" >/dev/null
done
echo "已生成 $out 中的全部尺寸"
