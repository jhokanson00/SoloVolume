#!/bin/zsh
# Publishes a GitHub Release with the .dmg attached, for the version in Info.plist.
# Bump CFBundleShortVersionString (and CFBundleVersion) in Info.plist first.
set -euo pipefail
cd "${0:A:h}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
TAG=v$VERSION

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes before releasing." >&2
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "$TAG already exists; bump the version in Info.plist." >&2
    exit 1
fi

./build.sh --dmg
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "build/SoloVolume-$VERSION.dmg" --title "SoloVolume $VERSION" --generate-notes
