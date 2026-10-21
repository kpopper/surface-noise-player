#!/usr/bin/env bash
# Builds a release of the macOS app and installs it into /Applications as
# the everyday copy, separate from the "Dev Surface Noise" app that debug
# and profile builds produce (each has its own bundle ID, so they keep
# separate databases and library folders).
#
# Usage: bash scripts/install_macos_release.sh
#
# The version name comes from pubspec.yaml, left as is; the build number is
# generated from the current time (YYYYMMDDHHMM), matching
# build_for_appstore.sh. The built commit is tagged macos/<version>-<build>
# locally as a record of what's installed. Any running copy is quit and the
# previous install replaced; its data in ~/Library/Containers is untouched.

set -e

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree has uncommitted changes — commit or stash them first," >&2
  echo "so the macos tag points at exactly what was built." >&2
  exit 1
fi

APP_NAME="Surface Noise"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUILT_APP="build/macos/Build/Products/Release/${APP_NAME}.app"

VERSION_NAME=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
BUILD_NUMBER=$(date +%Y%m%d%H%M)
TAG="macos/${VERSION_NAME}-${BUILD_NUMBER}"

echo "→ Building version ${VERSION_NAME} (${BUILD_NUMBER})…"
flutter build macos --release \
  --build-name="$VERSION_NAME" \
  --build-number="$BUILD_NUMBER"

if pgrep -xq "$APP_NAME"; then
  echo "→ Quitting the running copy…"
  osascript -e "tell application \"${APP_NAME}\" to quit"
  while pgrep -xq "$APP_NAME"; do sleep 0.5; done
fi

echo "→ Installing to ${INSTALL_PATH}…"
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

git tag "$TAG"
echo "→ Tagged $(git rev-parse --short HEAD) as ${TAG} (local only — git push origin ${TAG} to share it)."
echo "→ Installed. Open it from /Applications or Spotlight."
