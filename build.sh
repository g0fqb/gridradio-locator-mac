#!/bin/bash
set -euo pipefail

APP_NAME="GridRadio Locator"
BIN_NAME="GridRadioLocator"
BUNDLE_ID="uk.g0fqb.gridradiolocator"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/$APP_NAME.app"

echo "Compiling..."
swiftc -O "$DIR/main.swift" -o "$DIR/$BIN_NAME" \
  -framework CoreLocation -framework AppKit -framework MapKit \
  -framework Security -framework UniformTypeIdentifiers

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
chmod +x "$APP/Contents/MacOS/$BIN_NAME"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "Code signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "Done: $APP"
echo
echo "To install: cp -R \"$APP\" ~/Applications/ && xattr -dr com.apple.quarantine ~/Applications/\"$APP_NAME.app\""
echo
echo "First launch will prompt for a grid.radio API key (create one at https://grid.radio/developer/)"
echo "and store it in your macOS Keychain - it is never stored in this source."
