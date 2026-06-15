#!/bin/zsh
# MenuMate release pipeline: archive → Developer ID sign → dmg → notarize → staple → Sparkle sign.
#
# Requires (see docs/RELEASING.md):
#   DEVELOPER_ID_APP   "Developer ID Application: Your Name (TEAMID)"  (signing identity)
#   TEAM_ID            your Apple Developer Team ID
#   Notarization auth — EITHER a stored notarytool keychain profile:
#     NOTARY_PROFILE   profile name created via `notarytool store-credentials`
#   OR App Store Connect API key (used by CI):
#     NOTARY_KEY_ID, NOTARY_ISSUER, NOTARY_KEY_PATH (path to AuthKey_XXXX.p8)
#   Sparkle EdDSA key — locally read from the keychain by sign_update; in CI set:
#     SPARKLE_ED_PRIVATE_KEY  (base64 private key string)
#
# Usage: scripts/release.sh <version>     e.g. scripts/release.sh 1.0.0
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
ROOT="${0:A:h:h}"            # repo root (scripts/ -> ..)
cd "$ROOT"

: "${DEVELOPER_ID_APP:?set DEVELOPER_ID_APP}"
: "${TEAM_ID:?set TEAM_ID}"

BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/MenuMate.xcarchive"
EXPORT="$BUILD/export"
DMG="$BUILD/MenuMate-$VERSION.dmg"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "==> Generating project"
make gen >/dev/null

echo "==> Archiving (Release, Developer ID, hardened runtime)"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project MenuMate.xcodeproj -scheme MenuMate -configuration Release \
  -derivedDataPath "$ROOT/build" \
  archive -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" | tail -3

echo "==> Exporting Developer ID app"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" | tail -3
APP="$EXPORT/MenuMate.app"

echo "==> Building dmg"
STAGE="$BUILD/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MenuMate" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$DEVELOPER_ID_APP" --timestamp "$DMG"

echo "==> Notarizing dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER:?}" "${NOTARY_KEY_PATH:?}"
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
fi
xcrun stapler staple "$DMG"

echo "==> Sparkle: signing update"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  SIG=$("$SPARKLE_BIN/sign_update" "$DMG" --ed-key-file - <<< "$SPARKLE_ED_PRIVATE_KEY")
else
  SIG=$("$SPARKLE_BIN/sign_update" "$DMG")   # reads private key from the login keychain
fi
echo "    $SIG"

echo ""
echo "✅ Release artifact: $DMG"
echo "   Append this to appcast.xml's <item> (or run: $SPARKLE_BIN/generate_appcast <dir-of-dmgs>):"
echo "   version=$VERSION  $SIG"
