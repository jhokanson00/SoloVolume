#!/bin/zsh
# Builds SoloVolume.app (universal: Apple silicon + Intel) into ./build.
#   ./build.sh            build only
#   ./build.sh --install  also copy it to /Applications and relaunch it
#   ./build.sh --dmg      also package build/SoloVolume-<version>.dmg (notarized when Developer ID signed)
set -euo pipefail
cd "${0:A:h}"

APP=build/SoloVolume.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library \
        -target $arch-apple-macos14.2 \
        Sources/*.swift \
        -o build/SoloVolume-$arch
done
lipo -create build/SoloVolume-arm64 build/SoloVolume-x86_64 -output "$APP/Contents/MacOS/SoloVolume"
rm build/SoloVolume-arm64 build/SoloVolume-x86_64

# Sign with a Developer ID if one is in the keychain (override with SIGN_ID=...), else ad-hoc.
SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    codesign --force --sign - "$APP"
fi
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
