#!/bin/zsh
# 记录待移动项，配合「粘贴到此处」使用
printf '%s\n' "$@" > "$MENUMATE_DATA/cutbuffer"
echo "已剪切 $# 个项目"
