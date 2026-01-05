#!/bin/bash

# --- Configuration ---
APP_NAME="ClipTerminal"
SCHEME="ClipTerminal"
PROJECT="ClipTerminal.xcodeproj"
BUILD_DIR="/tmp/ClipTerminal-Build"
DMG_NAME="ClipTerminal.dmg"
# ---------------------

set -e # Exit on error

echo "🚀 Starting build process for $APP_NAME..."

# 1. Clean and Build the App
echo "📦 Building project..."
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build

# 2. Locate the built .app
# Usually in build/Build/Products/Release/ClipTerminal.app
BUILT_APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$BUILT_APP_PATH" ]; then
    echo "❌ Error: Could not find built .app file."
    exit 1
fi

echo "✅ Found built app at: $BUILT_APP_PATH"

# 3. Prepare DMG staging area
echo "📂 Preparing DMG content..."
STAGING_DIR=$(mktemp -d)
cp -R "$BUILT_APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 4. Create the DMG
echo "💿 Creating DMG..."
TMP_DMG="/tmp/$DMG_NAME"
rm -f "$TMP_DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$TMP_DMG"

mv "$TMP_DMG" "./$DMG_NAME"

# 5. Cleanup
echo "🧹 Cleaning up..."
rm -rf "$STAGING_DIR"
# rm -rf "$BUILD_DIR" # Uncomment if you want to delete build artifacts

echo "✨ Success! Created: $DMG_NAME"
