#!/bin/zsh
# Builds "Dott Tap.app" and a DMG into ./dist. Needs only the Xcode command-line tools.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$ROOT/dist/Dott Tap.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DottTap "$APP/Contents/MacOS/DottTap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET=$(mktemp -d)/AppIcon.iconset
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local certificate from scripts/setup-signing.sh when it exists: the app
# keeps the same identity, so macOS keeps its Accessibility permission across updates.
# Without it, fall back to an ad-hoc signature (permission must be re-allowed per build).
KC="$HOME/Library/Keychains/dott-tap-signing.keychain-db"
PASSFILE="$HOME/.config/dott-tap/keychain-pass"
if [[ -f "$KC" && -f "$PASSFILE" ]]; then
  security unlock-keychain -p "$(cat "$PASSFILE")" "$KC"
  IDENTITY=$(security find-identity -p codesigning "$KC" | awk '/"Dott Tap Local Signing"/ {print $2; exit}')
  codesign --force --sign "$IDENTITY" --keychain "$KC" --identifier in.opendott.tap "$APP"
  echo "Signed with Dott Tap Local Signing ($IDENTITY)"
else
  codesign --force --sign - --identifier in.opendott.tap "$APP"
  echo "Signed ad-hoc (run scripts/setup-signing.sh to keep permissions across updates)"
fi

DMG="$ROOT/dist/DottTap-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Dott Tap" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built: $APP"
echo "DMG:   $DMG"
