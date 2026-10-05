#!/bin/zsh
# Checks that a built SoloVolume.app is fit to hand to users, and fails loudly if not:
# signed with the developer's Developer ID and the hardened runtime, no entitlements at
# all (nothing that lets other code into the app), nothing else can drive it (no URL
# scheme, no AppleScript), libraries only from macOS, built for Apple silicon and Intel
# on the macOS it promises, and notarized. release.sh runs it on the app inside the .dmg.
#
#   ./check-app.sh path/to/SoloVolume.app [version]
set -euo pipefail

APP="${1:?Usage: ./check-app.sh path/to/SoloVolume.app [version]}"
VERSION="${2:-}"
BIN="$APP/Contents/MacOS/SoloVolume"
PLIST="$APP/Contents/Info.plist"
# The developer's team. Another team's Developer ID would pass Gatekeeper, but macOS
# would forget every permission users gave SoloVolume.
TEAM=DHGK36B2V9
fail() { echo "check-app: $*" >&2; exit 1; }
key() { plutil -extract "$1" raw "$PLIST" 2>/dev/null || echo "(missing)"; }

codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the signature doesn't verify"
info="$(codesign -dvv "$APP" 2>&1)"
grep -q '^Authority=Developer ID Application: ' <<<"$info" || fail "not signed with a Developer ID"
grep -q "^TeamIdentifier=$TEAM\$" <<<"$info" || fail "not signed by team $TEAM"
grep -q '^CodeDirectory .*flags=.*runtime' <<<"$info" || fail "doesn't use the hardened runtime"

# No entitlements. Anything here (library validation off, DYLD variables, get-task-allow,
# JIT, audio-input) would widen what the app or code injected into it could do.
ent="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
if [[ -n "$ent" && "$(plutil -convert json -o - - <<<"$ent")" != "{}" ]]; then
    fail "unexpected entitlements: $(plutil -convert json -o - - <<<"$ent")"
fi

# Nothing else can drive it.
[[ "$(key CFBundleURLTypes)" == "(missing)" ]] || fail "declares a URL scheme"
[[ "$(key NSAppleScriptEnabled)" != true ]] || fail "is scriptable with AppleScript"
[[ "$(key NSServices)" == "(missing)" ]] || fail "offers Services"

# Libraries come only from macOS: no @rpath, no embedded frameworks.
rpaths="$(otool -l "$BIN" | awk '/cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }' | sort -u)"
while IFS= read -r rpath; do
    case "$rpath" in
        /usr/lib/swift | "") ;;
        *) fail "unexpected library search path: $rpath" ;;
    esac
done <<<"$rpaths"
outside="$(otool -L "$BIN" | awk '/^\t/ { print $1 }' | grep -v -E '^(/usr/lib/|/System/Library/)' | sort -u || true)"
[[ -z "$outside" ]] || fail "links a library from outside macOS: $outside"

# Apple silicon and Intel, on every macOS it promises (LSMinimumSystemVersion).
MIN_OS="$(key LSMinimumSystemVersion)"
archs="$(lipo -archs "$BIN")"
[[ "$archs" == "x86_64 arm64" ]] || fail "built for $archs, not Apple silicon and Intel"
for arch in x86_64 arm64; do
    minos="$(vtool -arch "$arch" -show-build "$BIN" | awk '$1 == "minos" { print $2 }' | sed -n 1p)"
    [[ -n "$minos" && "$(printf '%s\n' "$minos" "$MIN_OS" | sort -V | sed -n 1p)" == "$minos" ]] \
        || fail "($arch) needs macOS ${minos:-?}, but SoloVolume promises $MIN_OS"
done

xcrun stapler validate -q "$APP" || fail "not notarized (no stapled ticket)"
spctl --assess --type execute "$APP" 2>/dev/null || fail "Gatekeeper rejects it"

if [[ -n "$VERSION" ]]; then
    built="$(key CFBundleShortVersionString)"
    [[ "$built" == "$VERSION" ]] || fail "it's version $built, not $VERSION"
fi
echo "check-app: $(basename "$APP") passes"
