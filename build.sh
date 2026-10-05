#!/bin/zsh
# Builds SoloVolume.app (universal: Apple silicon + Intel) into ./build.
#   ./build.sh            build only
#   ./build.sh --install  also copy it to /Applications and relaunch it
#   ./build.sh --dmg      also package build/SoloVolume-<version>.dmg
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

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

case "${1:-}" in
--install)
    pkill -x SoloVolume || true
    rm -rf /Applications/SoloVolume.app
    cp -R "$APP" /Applications/
    open /Applications/SoloVolume.app
    echo "Installed to /Applications/SoloVolume.app and launched it"
    ;;
--dmg)
    DMG=build/SoloVolume-$VERSION.dmg
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "SoloVolume $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "Packaged $DMG"
    ;;
esac
