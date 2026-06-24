#!/bin/zsh
# Dev helper: fix "MenuMate's Finder extension doesn't show up / won't enable".
#
# WHY THIS EXISTS
#   macOS tracks app extensions through Launch Services + pkd, keyed loosely by
#   bundle id. During development you accumulate many copies of the same bundle id
#   (DerivedData Debug/Release, exported archives, mounted DMGs, dmg staging dirs).
#   Launch Services does not garbage-collect registrations for paths that were
#   deleted/unmounted, so it can hand pkd a DEAD path as the "canonical" copy of
#   com.menumate.app — and pkd then can't activate the real FinderSync extension.
#   Symptom: the extension is absent from System Settings and isExtensionEnabled
#   stays false forever ("申请时候没有自己").
#
#   This script purges every registration for the MenuMate bundle ids, re-registers
#   the ONE real build, enables the extension, and restarts pkd + Finder so they
#   rescan. Run it whenever "右键菜单又没了" after a rebuild / DMG test.
#
# Usage:
#   scripts/dev-reset-extension.sh                 # uses the Debug build
#   scripts/dev-reset-extension.sh /path/to/MenuMate.app
set -euo pipefail

ROOT="${0:A:h:h}"                                  # repo root (scripts/ -> ..)
APP="${1:-$ROOT/build/Build/Products/Debug/MenuMate.app}"

HOST_ID="com.menumate.app"
EXT_ID="com.menumate.app.FinderExtension"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$APP" ]]; then
  echo "✗ App not found: $APP" >&2
  echo "  Build it first (e.g. \`make build\` / Xcode), or pass the .app path explicitly." >&2
  exit 1
fi
APPEX="$APP/Contents/PlugIns/FinderExtension.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "✗ Extension not found inside app: $APPEX" >&2
  exit 1
fi

echo "==> Live build: $APP"

# 1. Collect every path Launch Services has registered for the host bundle id,
#    including dead ones. Paths can contain spaces (e.g. /Volumes/MenuMate 1.0/…),
#    so strip the "path:" prefix and the trailing " (0x…)" hex id by hand.
echo "==> Purging stale Launch Services registrations for $HOST_ID"
typeset -a paths
while IFS= read -r p; do
  [[ -n "$p" ]] && paths+="$p"
done < <("$LSREG" -dump 2>/dev/null | awk -v id="$HOST_ID" '
  /^[[:space:]]*path:/ {
    line=$0
    sub(/^[[:space:]]*path:[[:space:]]*/, "", line)
    sub(/[[:space:]]*\([^)]*\)[[:space:]]*$/, "", line)
    cur=line
  }
  $0 ~ ("CFBundleIdentifier = \"" id "\";") { print cur }
' | sort -u)

if (( ${#paths} == 0 )); then
  echo "   (none registered yet — fresh machine)"
else
  for p in "${paths[@]}"; do
    "$LSREG" -u "$p" >/dev/null 2>&1 && echo "   unregistered: $p"
  done
fi

# 2. Re-register the one real copy (this re-registers the embedded appex too).
echo "==> Re-registering the live build"
"$LSREG" -f "$APP"

# 3. Enable the extension (dev convenience — the real onboarding asks the user to
#    toggle it in System Settings; here we just want it live immediately).
echo "==> Enabling extension election (use)"
/usr/bin/pluginkit -a "$APPEX" >/dev/null 2>&1 || true
/usr/bin/pluginkit -e use -i "$EXT_ID" >/dev/null 2>&1 || true

# 4. Restart the daemons so they rescan now instead of "eventually".
echo "==> Restarting pkd + Finder"
killall -9 pkd >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

# 5. Verify.
echo "==> Result:"
if /usr/bin/pluginkit -m -p com.apple.FinderSync -v 2>/dev/null | grep -q "$EXT_ID"; then
  /usr/bin/pluginkit -m -p com.apple.FinderSync -v 2>/dev/null | grep "$EXT_ID" | sed 's/^/   /'
  echo "✅ Registered. A leading '+' means enabled; '-' means ignored."
  echo "   If it's '-', toggle it on in System Settings ▸ Login Items & Extensions,"
  echo "   or just re-run this script."
else
  echo "✗ Still not registered. Things to check:" >&2
  echo "   • app & appex signed with the SAME Team ID (codesign -dv …)" >&2
  echo "   • app is NOT running from a quarantined/translocated path (move out of ~/Downloads)" >&2
  exit 1
fi
