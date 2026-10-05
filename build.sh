#!/bin/zsh
# Builds SoloVolume.app (universal: Apple silicon + Intel) into ./build.
#   ./build.sh            build only
#   ./build.sh --install  also copy it to /Applications and relaunch it
#   ./build.sh --dmg      also package build/SoloVolume-<version>.dmg (notarized when Developer ID signed)
set -euo pipefail
cd "${0:A:h}"

APP=build/SoloVolume.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN_DIR="$(swift build -c release $ARCHS --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/SoloVolume" "$APP/Contents/MacOS/SoloVolume"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"

# The only library loaded through @rpath is Sparkle, from inside the app. SwiftPM also
# adds its toolchain folder and @loader_path, which would be searched first; remove
# everything but the app's Frameworks folder and the system's Swift libraries.
otool -l "$APP/Contents/MacOS/SoloVolume" \
    | awk '/cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }' \
    | sort -u \
    | while IFS= read -r rpath; do
        case "$rpath" in
            "@executable_path/../Frameworks" | /usr/lib/swift) ;;
            *) install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/SoloVolume" ;;
        esac
    done

# Sparkle (updates). SoloVolume isn't sandboxed, so Sparkle's XPC services aren't needed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"

# Sign with a Developer ID if one is in the keychain (override with SIGN_ID=...), else
# ad-hoc. Hardened runtime always, so local builds behave like the notarized release.
SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
SIGN=(codesign --force --options runtime)
ENTITLEMENTS=()
if [[ -n "$SIGN_ID" ]]; then
    SIGN+=(--timestamp --sign "$SIGN_ID")
else
    # Without a Team ID the hardened runtime refuses to load Sparkle.framework, so ad-hoc
    # builds allow libraries signed by anyone. Never in a release: check-app.sh refuses
    # any entitlement.
    SIGN+=(--sign -)
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" build/local.entitlements >/dev/null
    ENTITLEMENTS=(--entitlements build/local.entitlements)
fi
# Inside out: Sparkle's helpers, the framework, then the app.
$SIGN "$SPARKLE/Versions/B/Autoupdate"
$SIGN "$SPARKLE/Versions/B/Updater.app"
$SIGN "$SPARKLE"
$SIGN $ENTITLEMENTS "$APP"
echo "Built $APP ($VERSION), signed by ${SIGN_ID:-ad-hoc}"

case "${1:-}" in
--install)
    pkill -x SoloVolume || true
    rm -rf /Applications/SoloVolume.app
    cp -R "$APP" /Applications/
    open /Applications/SoloVolume.app
    echo "Installed to /Applications/SoloVolume.app and launched it"
    ;;
--dmg)
    # Notarize with a notarytool profile (override with NOTARY_PROFILE=...), saved once via:
    #   xcrun notarytool store-credentials pane-notary --apple-id <email> --team-id <team>
    PROFILE=${NOTARY_PROFILE:-pane-notary}
    # notarytool exits 0 even when Apple rejects a submission, so check the status itself.
    notarize() {
        local out
        out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)"
        echo "$out"
        grep -q "status: Accepted" <<<"$out" || { echo "Notarization of $1 failed" >&2; exit 1; }
    }
    DMG=build/SoloVolume-$VERSION.dmg
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"

    # Notarize and staple the app itself first, so it passes Gatekeeper offline even once
    # it's been copied out of the .dmg.
    if [[ -n "$SIGN_ID" ]]; then
        ditto -c -k --keepParent "$APP" build/SoloVolume.zip
        notarize build/SoloVolume.zip
        rm build/SoloVolume.zip
        xcrun stapler staple "$APP"
    fi

    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "SoloVolume $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "Packaged $DMG"

    if [[ -n "$SIGN_ID" ]]; then
        codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
        notarize "$DMG"
        xcrun stapler staple "$DMG"
        spctl --assess --type open --context context:primary-signature -v "$DMG"
        echo "Notarized $DMG"
    fi
    ;;
esac
