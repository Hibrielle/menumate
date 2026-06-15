#!/bin/zsh
# 「前往上一层级目录」(右键文件/文件夹时触发,与右键空白处的同名动作互补,行为一致=上一层)。
# - 前台是 Finder:把前台窗口切到"当前所在文件夹的上一层"(不开新窗、不打断你)。
# - 前台是别的 App(如浏览器的上传/打开对话框):发 ⌘↑ 让该面板上一层。
# 需要的授权:Finder 路径用「自动化 › Finder」;⌘↑ 路径用「自动化 › System Events」+「辅助功能」。
# 均为一次性授权,可在首次引导「授予权限」里一并授予。

bid=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null)

if [[ "$bid" == *com.apple.finder* ]]; then
  osascript <<'APPLESCRIPT'
tell application "Finder"
  if (count of Finder windows) is 0 then return
  set w to front Finder window
  try
    set target of w to (container of (target of w))   -- 当前文件夹的上一层
  end try
end tell
APPLESCRIPT
else
  if ! osascript -e 'tell application "System Events" to key code 126 using command down' >/dev/null 2>&1; then
    print -u2 "需在『系统设置 › 隐私与安全性 › 辅助功能』勾选 MenuMate,才能在上传/打开对话框里上一层。"
    exit 1
  fi
fi
