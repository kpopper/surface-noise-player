#!/usr/bin/env bash
# Builds a release IPA for App Store Connect/TestFlight, bumping the app
# version, and opens the resulting archive in Xcode's Organizer for a
# manual upload — `flutter build ipa` writes its archive into
# build/ios/archive instead of Xcode's own Archives folder, so Organizer
# never lists it on its own unless it's opened directly like this.
#
# Usage: bash scripts/build_for_appstore.sh [major|minor|patch]
#   Defaults to a patch bump. The build number (the +N after the version)
#   always increments by one regardless of which part is bumped, since App
#   Store Connect rejects a build whose number isn't higher than every
#   build previously uploaded for this app.

set -e

BUMP="${1:-patch}"
case "$BUMP" in
  major|minor|patch) ;;
  *)
    echo "Usage: $0 [major|minor|patch]" >&2
    exit 1
    ;;
esac

CURRENT_VERSION=$(grep '^version:' pubspec.yaml)
MAJOR=$(echo "$CURRENT_VERSION" | sed -E 's/version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)/\1/')
MINOR=$(echo "$CURRENT_VERSION" | sed -E 's/version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)/\2/')
PATCH=$(echo "$CURRENT_VERSION" | sed -E 's/version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)/\3/')
BUILD_NUMBER=$(echo "$CURRENT_VERSION" | sed -E 's/version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)/\4/')

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"

sed -i '' "s/^version: .*/version: ${NEW_VERSION_NAME}+${NEW_BUILD_NUMBER}/" pubspec.yaml
git add pubspec.yaml
git commit -m "Bump version to ${NEW_VERSION_NAME}+${NEW_BUILD_NUMBER} for TestFlight upload"

echo "→ Building version ${NEW_VERSION_NAME}+${NEW_BUILD_NUMBER}…"
flutter build ipa --release

open build/ios/archive/Runner.xcarchive
echo "→ Opened the archive in Xcode Organizer — use Distribute App to upload it."
