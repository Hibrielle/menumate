#!/bin/zsh
# 在终端打开选中目录(文件取其父目录)。
# 默认终端由 MenuMate「通用 > 默认终端」决定(经 MENUMATE_TERMINAL 传入 bundle id);
# 未设则用系统 Terminal。也可直接改本脚本换成你想要的终端。
term="${MENUMATE_TERMINAL:-com.apple.Terminal}"
for p in "$@"; do
  [[ -d "$p" ]] || p="${p:h}"
  open -b "$term" "$p" 2>/dev/null || open -a Terminal "$p"
done
