#!/usr/bin/env bash
# Builds a release IPA for App Store Connect/TestFlight and opens the
# resulting archive in Xcode's Organizer for a manual upload —
# `flutter build ipa` writes its archive into build/ios/archive instead of
# Xcode's own Archives folder, so Organizer never lists it on its own
# unless it's opened directly like this.
#
# Usage: bash scripts/build_for_appstore.sh
#
# Nothing is committed. The version name (e.g. 1.0.1) comes from
# pubspec.yaml and only changes when it's deliberately bumped there —
# TestFlight accepts any number of builds of the same version. The build
# number is generated from the current time (YYYYMMDDHHMM), so it always
# increases, as App Store Connect requires, without having to record the
# last one anywhere. The built commit is tagged testflight/<version>-<build>
# locally as a record of what was uploaded.

set -e

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree has uncommitted changes — commit or stash them first," >&2
  echo "so the testflight tag points at exactly what was built." >&2
  exit 1
fi

VERSION_NAME=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
BUILD_NUMBER=$(date +%Y%m%d%H%M)
TAG="testflight/${VERSION_NAME}-${BUILD_NUMBER}"

echo "→ Building version ${VERSION_NAME} (${BUILD_NUMBER})…"
flutter build ipa --release \
  --build-name="$VERSION_NAME" \
  --build-number="$BUILD_NUMBER"

git tag "$TAG"
echo "→ Tagged $(git rev-parse --short HEAD) as ${TAG} (local only — git push origin ${TAG} to share it)."

open build/ios/archive/Runner.xcarchive
echo "→ Opened the archive in Xcode Organizer — use Distribute App to upload it."
