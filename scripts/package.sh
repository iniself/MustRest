#!/bin/bash
set -euo pipefail

APP_NAME="MustRestApp"
BUNDLE_NAME="MustRest"
BUNDLE_ID="com.iniself.mustrest"
VERSION="1.0.0"
ICON="icon/eyes.icns"
OUT_DIR="dist"

swift build -c release

STAGE="$(mktemp -d)"
APP_DIR="${STAGE}/${BUNDLE_NAME}.app"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
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
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>eyes</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --sign - --force "${APP_DIR}"

ln -s /Applications "${STAGE}/Applications"
rm -f "${OUT_DIR}/${BUNDLE_NAME}-${VERSION}.dmg"
rm -rf "${OUT_DIR}/${BUNDLE_NAME}.app" "${OUT_DIR}/.DS_Store"
hdiutil create -volname "${BUNDLE_NAME}" -srcfolder "${STAGE}" -format UDZO -o "${OUT_DIR}/${BUNDLE_NAME}-${VERSION}.dmg"
rm -rf "${STAGE}"

echo "Packaged ${BUNDLE_NAME}-${VERSION}.dmg"
