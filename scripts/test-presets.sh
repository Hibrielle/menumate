#!/bin/zsh
# 预设脚本的确定性行为测试(不依赖 Finder/剪贴板,CI 可跑)。
# 覆盖:new-file 模板复制 + 自动重名编号;cut+paste 经 cutbuffer 移动。
set -euo pipefail
ROOT="${0:A:h:h}"
PRESETS="$ROOT/App/PresetScripts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# 屏蔽 new-file 里的 `open -R`(测试环境不弹 Finder)
stub="$T/bin"; mkdir -p "$stub"; printf '#!/bin/zsh\nexit 0\n' > "$stub/open"; chmod +x "$stub/open"
export PATH="$stub:$PATH"

fail() { print -u2 "FAIL: $1"; exit 1 }

# --- new-file: 模板复制 + 自动编号 ---
tpl="$T/templates"; mkdir -p "$tpl"; print "hello" > "$tpl/Note.md"
work="$T/work"; mkdir -p "$work"
MENUMATE_TEMPLATES="$tpl" MENUMATE_VARIANT="Note.md" /bin/zsh "$PRESETS/new-file.sh" "$work" >/dev/null
[[ -f "$work/Note.md" ]] || fail "new-file 未创建 Note.md"
MENUMATE_TEMPLATES="$tpl" MENUMATE_VARIANT="Note.md" /bin/zsh "$PRESETS/new-file.sh" "$work" >/dev/null
[[ -f "$work/Note 2.md" ]] || fail "new-file 未自动编号为 'Note 2.md'"

# --- cut + paste: 经 cutbuffer 移动 ---
data="$T/data"; mkdir -p "$data"
src="$T/src"; mkdir -p "$src"; print x > "$src/a.txt"; print y > "$src/b.txt"
dst="$T/dst"; mkdir -p "$dst"
MENUMATE_DATA="$data" /bin/zsh "$PRESETS/cut.sh" "$src/a.txt" "$src/b.txt" >/dev/null
[[ -s "$data/cutbuffer" ]] || fail "cut 未写 cutbuffer"
MENUMATE_DATA="$data" /bin/zsh "$PRESETS/paste.sh" "$dst" >/dev/null
[[ -f "$dst/a.txt" && -f "$dst/b.txt" ]] || fail "paste 未移动到目标"
[[ ! -e "$src/a.txt" && ! -e "$src/b.txt" ]] || fail "paste 未从源删除(应为移动)"
[[ ! -e "$data/cutbuffer" ]] || fail "paste 未清空 cutbuffer"

print "✓ preset scripts: new-file (auto-number) + cut/paste (move) pass"
