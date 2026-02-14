#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/macos"
BUILD_DIR="${ROOT_DIR}/build/macos"
APP_NAME="musicPlayer"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
BIN_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${BIN_DIR}" "${RES_DIR}"
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>guoxh.musicPlayerMac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
TARGET_ARCH="$(uname -m)"
TARGET="${TARGET_ARCH}-apple-macosx13.0"

swiftc \
  -sdk "${SDK_PATH}" \
  -emit-executable \
  -o "${BIN_DIR}/${APP_NAME}" \
  "${SRC_DIR}/musicPlayerMacApp.swift" \
  "${SRC_DIR}/ContentView.swift" \
  "${SRC_DIR}/SidebarView.swift" \
  "${SRC_DIR}/PlayerViewModel.swift" \
  "${SRC_DIR}/LyricFetcher.swift" \
  "${SRC_DIR}/AlbumArtFetcher.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Cocoa \
  -framework AVFoundation \
  -framework UniformTypeIdentifiers \
  -framework Combine \
  -target "${TARGET}"

/usr/bin/codesign --force --deep --sign - "${APP_DIR}" || true
xattr -dr com.apple.quarantine "${APP_DIR}" || true
echo "Built app at: ${APP_DIR}"

ICON_SRC=""
if [ -f "${ROOT_DIR}/musicPlayer/Assets.xcassets/AppIconMain.appiconset/AppIconMain-1024.png" ]; then
  ICON_SRC="${ROOT_DIR}/musicPlayer/Assets.xcassets/AppIconMain.appiconset/AppIconMain-1024.png"
elif [ -f "${ROOT_DIR}/musicPlayer/musicPlayer/guitar.png" ]; then
  ICON_SRC="${ROOT_DIR}/musicPlayer/musicPlayer/guitar.png"
elif [ -f "${ROOT_DIR}/musicPlayer/musicPlayer/guitar.jpeg" ]; then
  ICON_SRC="${ROOT_DIR}/musicPlayer/musicPlayer/guitar.jpeg"
fi

if [ -n "${ICON_SRC}" ]; then
  ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
  mkdir -p "${ICONSET_DIR}"
  sips -z 16 16   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  cp "${ICON_SRC}" "${ICONSET_DIR}/icon_512x512.png"
  cp "${ICON_SRC}" "${ICONSET_DIR}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET_DIR}" -o "${RES_DIR}/AppIcon.icns" || true
fi
