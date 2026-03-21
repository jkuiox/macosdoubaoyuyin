#!/bin/bash
set -e

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"

APP_NAME="yapyap"
SCHEME="yapyap"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "==> Generating Xcode project..."
xcodegen generate -q

echo "==> Building $APP_NAME (Release, arm64)..."
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -arch arm64 \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_ENTITLEMENTS="$SCRIPT_DIR/yapyap.entitlements" \
    clean build 2>&1 | tail -1

echo "==> Code signing..."
codesign --force --deep --sign "Apple Development: cnskyrin@gmail.com" \
    --entitlements "$SCRIPT_DIR/yapyap.entitlements" \
    "$APP_BUNDLE"

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"

echo ""
echo "✅ Done!"
echo "   App:  $APP_BUNDLE"
echo "   DMG:  $DMG_PATH"
echo ""
echo "Install: open $DMG_PATH  (drag to Applications)"
echo "   — or: cp -R $APP_BUNDLE /Applications/"
