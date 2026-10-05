#!/bin/zsh
# Builds, notarizes, checks and publishes a GitHub Release for the version in Info.plist.
#   1. Bump CFBundleShortVersionString and CFBundleVersion in Info.plist.
#   2. Write docs/release-notes/<version>.md.
#   3. Commit on main, then: ./release.sh            (or ./release.sh --dry-run to stop before publishing)
# Releases are immutable once published, and v* tags can't be moved or deleted.
set -euo pipefail
cd "${0:A:h}"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Info.plist)
TAG=v$VERSION
NOTES=docs/release-notes/$VERSION.md
DMG=build/SoloVolume-$VERSION.dmg

# Only committed source on main goes out, never a local experiment.
if [[ $DRY_RUN == 0 ]]; then
    [[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || { echo "Check out main first." >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; git status --short >&2; exit 1; }
    ! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "$TAG already exists; bump the version in Info.plist." >&2; exit 1; }
fi
[[ -f "$NOTES" ]] || { echo "Write the release notes in $NOTES first." >&2; exit 1; }

./build.sh --dmg

# Check the app exactly as users will get it: from inside the .dmg.
MOUNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
./check-app.sh "$MOUNT/SoloVolume.app" "$VERSION"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
{
    cat "$NOTES"
    echo
    echo "Download **SoloVolume-$VERSION.dmg** below, open it, and drag SoloVolume to Applications."
    echo "Requires macOS $MIN_OS or later. Runs on Apple silicon and Intel."
    echo
    echo "SHA-256 of \`SoloVolume-$VERSION.dmg\`: \`$SHA\`"
} > build/release-notes.md

if [[ $DRY_RUN == 1 ]]; then
    echo "Dry run: built and checked $DMG; not publishing. Notes:"
    cat build/release-notes.md
    exit 0
fi

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --title "SoloVolume $VERSION" --notes-file build/release-notes.md
