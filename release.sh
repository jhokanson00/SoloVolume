#!/bin/zsh
# Builds, notarizes, checks, signs for Sparkle and publishes a GitHub Release for the version in Info.plist.
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
REPO=jhokanson00/SoloVolume

# Only committed source on main goes out, never a local experiment.
if [[ $DRY_RUN == 0 ]]; then
    [[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || { echo "Check out main first." >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; git status --short >&2; exit 1; }
    ! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "$TAG already exists; bump the version in Info.plist." >&2; exit 1; }
fi
[[ -f "$NOTES" ]] || { echo "Write the release notes in $NOTES first." >&2; exit 1; }

# Sparkle offers an update only when its build number is higher than the installed one.
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
LATEST=$(gh release download -R "$REPO" --pattern appcast.xml --output - 2>/dev/null \
    | sed -n 's|.*<sparkle:version>\(.*\)</sparkle:version>.*|\1|p' | head -1 || true)
if [[ -n "$LATEST" ]] && (( BUILD <= LATEST )); then
    echo "CFBundleVersion is $BUILD, but the latest release is build $LATEST; bump it." >&2
    exit 1
fi

./build.sh --dmg

# Check the app exactly as users will get it: from inside the .dmg.
MOUNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
scripts/check-app.sh "$MOUNT/SoloVolume.app" "$VERSION"

# Sparkle: the update is the .dmg itself, signed with the EdDSA key in the keychain (made
# by generate_keys --account SoloVolume; its public half is SUPublicEDKey in Info.plist).
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
PUBLIC_KEY="$(cat scripts/sparkle-public-key.txt)"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account SoloVolume "$DMG")"
# The notes are embedded as HTML, so Sparkle's window shows them without loading GitHub.
NOTES_HTML="$(swift scripts/notes-html.swift "$NOTES")"
[[ "$NOTES_HTML" != *"]]>"* ]] || { echo "$NOTES can't contain ']]>'." >&2; exit 1; }
cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SoloVolume</title>
    <item>
      <title>SoloVolume $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/SoloVolume-$VERSION.dmg"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
# Sign the feed itself, so a changed appcast (other notes, links, versions) is refused
# (SURequireSignedFeed). Nothing may edit it after this. sign_update signs even XML it
# can't parse, so check it parses, and check both signatures against the public key
# users have, not the keychain's.
xmllint --noout build/appcast.xml
"$SPARKLE_BIN/sign_update" --account SoloVolume build/appcast.xml
xmllint --noout build/appcast.xml
swift scripts/verify-signature.swift "$PUBLIC_KEY" build/appcast.xml
swift scripts/verify-signature.swift "$PUBLIC_KEY" "$DMG" \
    "$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE")"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
{
    cat "$NOTES"
    echo
    echo "Download **SoloVolume-$VERSION.dmg** below, open it, and drag SoloVolume to Applications."
    echo "Already have it? Click the speaker in the menu bar and choose **Check for Updates…**."
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
gh release create "$TAG" "$DMG" build/appcast.xml --title "SoloVolume $VERSION" --notes-file build/release-notes.md
