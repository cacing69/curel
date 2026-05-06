#!/bin/bash
set -e

# Usage: ./fdroid-build.sh [major|minor]
#   major - bump minor version, reset patch, increment build
#   minor - bump patch version, increment build (default)

MODE=${1:-minor}

# Parse current version from pubspec.yaml
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
VERSION=$(echo "$CURRENT" | cut -d+ -f1)
BUILD=$(echo "$CURRENT" | cut -d+ -f2)

MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
PATCH=$(echo "$VERSION" | cut -d. -f3)

NEW_BUILD=$((BUILD + 1))

case "$MODE" in
  major)
    NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
    ;;
  minor)
    NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
    ;;
  *)
    echo "Usage: $0 [major|minor]"
    exit 1
    ;;
esac

# Update pubspec.yaml
sed -i '' "s/^version: .*/version: ${NEW_VERSION}+${NEW_BUILD}/" pubspec.yaml

echo "Version: $CURRENT-> ${NEW_VERSION}+${NEW_BUILD}"

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

# Commit and push to fdroid repo (subshell so cwd returns after)
(cd "$FDROID_REPO"
 git add .
 git commit -m "update curel to $NEW_VERSION"
 git push origin main)

echo "Done: curel $NEW_VERSION released"
