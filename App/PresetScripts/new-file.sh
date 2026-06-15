#!/bin/zsh
# 按模板在当前目录新建文件
# $1 = 目标目录；MENUMATE_VARIANT = 模板文件名；MENUMATE_TEMPLATES = 模板目录
set -e
template="$MENUMATE_TEMPLATES/$MENUMATE_VARIANT"
name="${MENUMATE_VARIANT%.*}"
ext="${MENUMATE_VARIANT##*.}"
[[ "$name" == "$MENUMATE_VARIANT" ]] && ext=""
dest="$1/$MENUMATE_VARIANT"
n=2
while [[ -e "$dest" ]]; do
  if [[ -n "$ext" ]]; then dest="$1/$name $n.$ext"; else dest="$1/$name $n"; fi
  n=$((n+1))
done
cp "$template" "$dest"
open -R "$dest"
echo "${dest##*/}"
