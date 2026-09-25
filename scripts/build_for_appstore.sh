#!/usr/bin/env bash
# Builds a release IPA for App Store Connect/TestFlight and opens the
# resulting archive in Xcode's Organizer for a manual upload —
# `flutter build ipa` writes its archive into build/ios/archive instead of
# Xcode's own Archives folder, so Organizer never lists it on its own
# unless it's opened directly like this.
#
# Usage: bash scripts/build_for_appstore.sh [major|minor|patch]
#
# The version name (e.g. 1.0.1) comes from pubspec.yaml. With no argument
# it's left as is and nothing is committed — TestFlight accepts any number
# of builds of the same version. Passing major/minor/patch bumps it first
# (resetting the parts below) and commits that bump, as a deliberate new
# version; that's refused on main, so it goes through a PR. The build
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

BUMP="$1"
case "$BUMP" in
  ""|major|minor|patch) ;;
  *)
    echo "Usage: $0 [major|minor|patch]" >&2
    exit 1
    ;;
esac

VERSION_NAME=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

if [ -n "$BUMP" ]; then
  if [ "$(git branch --show-current)" = "main" ]; then
    echo "Refusing to commit a version bump on main — switch to a branch first." >&2
    exit 1
  fi
  IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION_NAME"
  case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
  VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"
  # Only the version name is replaced; any +N suffix is left alone, since
  # the build number passed below overrides it anyway.
  sed -i '' -E "s/^version: [0-9]+\.[0-9]+\.[0-9]+/version: ${VERSION_NAME}/" pubspec.yaml
  git add pubspec.yaml
  git commit -m "Bump version to ${VERSION_NAME}"
fi

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
