#!/bin/zsh
# 用 sips 转换图片格式。MENUMATE_VARIANT = 目标格式（png/jpeg/heic/tiff）
set -e
fmt="$MENUMATE_VARIANT"
for f in "$@"; do
  base="${f%.*}"
  out="$base.$fmt"
  n=2
  while [[ -e "$out" ]]; do out="$base $n.$fmt"; n=$((n+1)); done
  sips -s format "$fmt" "$f" --out "$out" >/dev/null
done
echo "已转换 $# 个文件为 $fmt"
