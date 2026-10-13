#!/bin/sh
# © Pexilim
# Builds the free Mac download: a Release build, ad-hoc signed (no paid Apple account needed), in a DMG with a
# checksum. macOS asks once to "Open Anyway" because it isn't notarized (see marketing/site/install.html).
# Usage: apps/Blink/scripts/release.sh            → apps/Blink/build/release/Blink-<version>.dmg
# Needs Config/Local.xcconfig for the bundle ID prefix and the sign-in helper address.
# shortcut: ad-hoc signed and not notarized; switch to Developer ID + notarytool when the Apple Developer Program is paid.
set -eu
cd "$(dirname "$0")/.."
OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild -project Blink.xcodeproj -scheme Blink -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$OUT/derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ENTITLEMENTS="$PWD/Config/Blink-macOS-free.entitlements" \
  build -quiet

APP="$OUT/derived/Build/Products/Release/Blink.app"
codesign --verify --deep --strict "$APP"
# The download must be as protected as the Xcode build: sandboxed, with calendar access, and no debugging entitlement.
ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null)
for key in app-sandbox network.client personal-information.calendars; do
  echo "$ENT" | grep -q "com.apple.security.$key" || { echo "error: the build lacks com.apple.security.$key"; exit 1; }
done
if echo "$ENT" | grep -q get-task-allow; then echo "error: debugging entitlement in a release build"; exit 1; fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
HELPER=$(/usr/libexec/PlistBuddy -c "Print BlinkSigninHelper" "$APP/Contents/Info.plist" 2>/dev/null || true)
[ -n "$HELPER" ] || echo "warning: no BLINK_SIGNIN_HELPER in Local.xcconfig: this build offers only 'I already have a server'."

# The DMG: Blink, a link to Applications to drag it onto, and where to read how to open it the first time.
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Blink.app"
ln -s /Applications "$STAGE/Applications"
printf '[InternetShortcut]\nURL=https://blink.pexilim.com/install.html\n' > "$STAGE/How to open Blink.url"
DMG="$OUT/Blink-$VERSION.dmg"
hdiutil create -volname "Blink $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
shasum -a 256 "$DMG" | tee "$DMG.sha256"
# The site links to a fixed name; keep a copy under it.
cp "$DMG" "$OUT/Blink.dmg"
# The build folder is about 1 GB; the DMG has everything.
rm -rf "$OUT/derived" "$STAGE"
echo "Built $DMG"
