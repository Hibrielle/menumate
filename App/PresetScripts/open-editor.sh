#!/bin/zsh
# 用编辑器打开选中项。
# 默认编辑器由 MenuMate「通用 > 默认编辑器」决定(经 MENUMATE_EDITOR 传入 bundle id);
# 未设则用 VS Code,都不可用时回退系统默认文本编辑器。
editor="${MENUMATE_EDITOR:-com.microsoft.VSCode}"
open -b "$editor" "$@" 2>/dev/null || open -t "$@"
