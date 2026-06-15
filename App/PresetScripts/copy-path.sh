#!/bin/zsh
# 复制选中项的绝对路径到剪贴板（多选按行拼接）
printf '%s\n' "$@" | pbcopy
echo "已复制 $# 个路径"
