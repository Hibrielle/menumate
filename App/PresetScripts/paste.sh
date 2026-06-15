#!/bin/zsh
# 把已剪切的项目移动到当前目录（$1）
set -e
buffer="$MENUMATE_DATA/cutbuffer"
if [[ ! -s "$buffer" ]]; then
  echo "没有已剪切的项目" >&2
  exit 1
fi
moved=0
while IFS= read -r src; do
  [[ -e "$src" ]] || continue
  name="${src##*/}"
  base="${name%.*}"
  ext="${name##*.}"
  [[ "$base" == "$name" ]] && ext=""
  [[ -z "$base" ]] && { base="$name"; ext=""; }
  dest="$1/$name"
  n=2
  while [[ -e "$dest" ]]; do
    if [[ -n "$ext" ]]; then dest="$1/$base $n.$ext"; else dest="$1/$base $n"; fi
    n=$((n+1))
  done
  mv "$src" "$dest"
  moved=$((moved+1))
done < "$buffer"
rm -f "$buffer"
echo "已移动 $moved 个项目"
