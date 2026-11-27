#!/bin/bash
set -euo pipefail

APP_NAME="MustRestApp"
BUNDLE_NAME="MustRest"
BUNDLE_ID="com.iniself.mustrest"
ICON="icon/eyes.icns"
OUT_DIR="dist"

# Version resolution order: first script argument, then the VERSION
# environment variable, then the most recent git tag (with a leading "v"
# stripped). The build number is the commit count, so it grows whenever new
# code is committed; it can be overridden with BUILD_NUMBER.
VERSION="${1:-${VERSION:-}}"
if [ -z "${VERSION}" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "${VERSION}" ]; then
    echo "Missing version: pass it as an argument, e.g. ./scripts/package.sh 1.2.0" >&2
    exit 1
fi
# Only allow 1.2 or 1.2.3 style versions so the bundle gets a valid version.
if ! [[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid version: ${VERSION} (expected e.g. 1.2 or 1.2.3)" >&2
    exit 1
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# 分别编译 Intel 和 Apple Silicon 版本
swift build -c release --arch x86_64
swift build -c release --arch arm64

# 合并成 Universal Binary
mkdir -p "${OUT_DIR}"
lipo -create \
    ".build/x86_64-apple-macosx/release/${APP_NAME}" \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    -output "${OUT_DIR}/${APP_NAME}"

STAGE="$(mktemp -d)"
APP_DIR="${STAGE}/${BUNDLE_NAME}.app"

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${OUT_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${ICON}" "${APP_DIR}/Contents/Resources/"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${BUNDLE_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${BUNDLE_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>eyes</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --sign - --force "${APP_DIR}"

ln -s /Applications "${STAGE}/Applications"

rm -f "${OUT_DIR}/${BUNDLE_NAME}-${VERSION}.dmg" "${OUT_DIR}/${BUNDLE_NAME}-${VERSION}-universal.dmg"
rm -rf "${OUT_DIR}/${BUNDLE_NAME}.app" "${OUT_DIR}/.DS_Store"

cp -R "${APP_DIR}" "${OUT_DIR}/${BUNDLE_NAME}.app"

hdiutil create \
    -volname "${BUNDLE_NAME}" \
    -srcfolder "${STAGE}" \
    -format UDZO \
    -o "${OUT_DIR}/${BUNDLE_NAME}-${VERSION}-universal.dmg"

rm -rf "${STAGE}"
rm -f "${OUT_DIR}/${APP_NAME}"

echo "Packaged Universal Binary: ${BUNDLE_NAME}-${VERSION}-universal.dmg (version ${VERSION}, build ${BUILD_NUMBER})"
