#!/bin/zsh
# 「前往上一层级目录」:在当前文件浏览器里上一层(不开新窗、不打断你)。
# - 前台是 Finder:用 AppleScript 把前台 Finder 窗口切到父目录(需「自动化 › Finder」授权,一次性)。
# - 前台是别的 App(如浏览器的上传/打开对话框):发 ⌘↑——macOS 的打开/保存面板原生支持
#   ⌘↑ 上一层(需「辅助功能」授权,一次性)。
# 右键文件夹空白处触发;$1 = 当前文件夹路径。
cur="${1:-$PWD}"
parent="${cur:h}"

bid=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null)

if [[ "$bid" == *com.apple.finder* ]]; then
  [[ "$parent" == "$cur" ]] && exit 0   # 已在根,无上一层
  osascript - "$parent" <<'APPLESCRIPT'
on run argv
  set parentPath to item 1 of argv
  tell application "Finder"
    if (count of Finder windows) is 0 then return
    set target of front Finder window to (POSIX file parentPath as alias)
  end tell
end run
APPLESCRIPT
else
  # 非 Finder(上传/打开对话框等):发 ⌘↑ 让该面板上一层。
  if ! osascript -e 'tell application "System Events" to key code 126 using command down' >/dev/null 2>&1; then
    print -u2 "需在『系统设置 › 隐私与安全性 › 辅助功能』勾选 MenuMate,才能在上传/打开对话框里上一层。"
    exit 1
  fi
fi
