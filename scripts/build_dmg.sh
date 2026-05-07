#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${HOME}/Library/Developer/Xcode/DerivedData/Record-gqlilwpdkfoeqfbughqjzwwkpkkb"
PROJECT_PATH="${ROOT_DIR}/Record.xcodeproj"
SCHEME="Record"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILD_DIR="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}"
APP_PATH="${BUILD_DIR}/Record.app"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="${DIST_DIR}/Record-dmg-staging"
DMG_PATH="${DIST_DIR}/Record-${CONFIGURATION}.dmg"
VOLNAME="Record"

mkdir -p "${DIST_DIR}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Record.app not found at ${APP_PATH}" >&2
  exit 1
fi

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_PATH}" "${STAGING_DIR}/Record.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${VOLNAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGING_DIR}"
echo "Created ${DMG_PATH}"
