#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MACOS_DIR="$PROJECT_ROOT/macos"
BUILD_DIR="$MACOS_DIR/.build"
OUTPUT_DIR="$PROJECT_ROOT/dist"
APP_NAME="BeamDrop"
APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"

echo "=== Building ${APP_NAME} for macOS ==="

mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# Source files
SOURCES=($(find "$MACOS_DIR/Sources/BeamDrop" -name "*.swift"))


SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
MODULE_CACHE="/tmp/beamdrop-clang-cache"
mkdir -p "$MODULE_CACHE"

echo "Compiling Swift sources..."
swiftc \
    -module-name BeamDrop \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -O \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/BeamDrop"

echo "Creating Application Bundle at ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/BeamDrop" "$APP_BUNDLE/Contents/MacOS/"
cp "$MACOS_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

chmod +x "$APP_BUNDLE/Contents/MacOS/BeamDrop"

echo "Signing Application Bundle..."
codesign --force --deep --sign - -r '=designated => identifier "com.beamdrop.BeamDrop"' --entitlements "$MACOS_DIR/Resources/BeamDrop.entitlements" "$APP_BUNDLE" || true

echo "✓ Successfully built ${APP_BUNDLE}"
ls -la "$APP_BUNDLE/Contents/MacOS"
file "$APP_BUNDLE/Contents/MacOS/BeamDrop"
