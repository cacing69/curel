#!/bin/bash
set -e

# Usage: ./fdroid-build.sh [major|minor]
#   minor - bump patch (default): 1.3.4 → 1.3.5  build 10305
#   major - bump minor, reset patch: 1.3.4 → 1.4.0  build 10400
#
#   Build number = MAJOR * 10000 + MINOR * 100 + PATCH

MODE=${1:-minor}

# Parse current version from pubspec.yaml
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
VERSION=$(echo "$CURRENT" | cut -d+ -f1)

MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
PATCH=$(echo "$VERSION" | cut -d. -f3)

case "$MODE" in
  major)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$((MINOR + 1))
    NEW_PATCH=0
    ;;
  minor)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$MINOR
    NEW_PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Usage: $0 [major|minor]"
    exit 1
    ;;
esac

NEW_VERSION="$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"
NEW_BUILD=$((NEW_MAJOR * 10000 + NEW_MINOR * 100 + NEW_PATCH))

# Read changelog from NOTES.txt
NOTES_FILE="NOTES.txt"
CHANGELOG=""
if [ -f "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
  CHANGELOG=$(cat "$NOTES_FILE")
  echo "Changelog loaded from $NOTES_FILE"
else
  echo "Warning: $NOTES_FILE is empty or missing — changelog will be skipped"
fi

# Update pubspec.yaml
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: ${NEW_VERSION}+${NEW_BUILD}/" pubspec.yaml
else
  sed -i "s/^version: .*/version: ${NEW_VERSION}+${NEW_BUILD}/" pubspec.yaml
fi

echo "Version: $CURRENT -> ${NEW_VERSION}+${NEW_BUILD}"

# Build and release the APK for Android using Flutter
flutter build apk --release --split-per-abi

# Verify APKs exist before copying
SRC=build/app/outputs/flutter-apk
for arch in arm64-v8a armeabi-v7a x86_64; do
  if [ ! -f "$SRC/app-${arch}-release.apk" ]; then
    echo "Error: app-${arch}-release.apk not found"
    exit 1
  fi
done

# Copy the generated APKs to the fdroid repo directory
FDROID_REPO=~/Development/github/cacing69-fdroid/repo

cp "$SRC/app-arm64-v8a-release.apk" "$FDROID_REPO/dev.cacing69.curel-arm64-v8a.apk"
cp "$SRC/app-armeabi-v7a-release.apk" "$FDROID_REPO/dev.cacing69.curel-armeabi-v7a.apk"
cp "$SRC/app-x86_64-release.apk" "$FDROID_REPO/dev.cacing69.curel-x86_64.apk"

echo "Copied 3 APKs to $FDROID_REPO"

# Write changelog to fdroid metadata (subshell)
if [ -n "$CHANGELOG" ]; then
  LOCAL_CHANGELOG_FILE="./fastlane/metadata/android/en-US/changelogs/$NEW_BUILD.txt"

  mkdir -p "$(dirname "$LOCAL_CHANGELOG_FILE")"
  echo "$CHANGELOG" > "$LOCAL_CHANGELOG_FILE"
  echo "Changelog written to $LOCAL_CHANGELOG_FILE"
fi

# Commit and push to fdroid repo (subshell so cwd returns after)
(cd "$FDROID_REPO"
 cd ..
 git add .
 git commit -m "update curel to $NEW_VERSION"
 git push origin main)

# Clear NOTES.txt after successful build
if [ -n "$CHANGELOG" ]; then
  > "$NOTES_FILE"
  echo "Cleared $NOTES_FILE"
fi

echo "Done: curel $NEW_VERSION released"
