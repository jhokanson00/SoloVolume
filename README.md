<img src="Icon/preview.png" width="128" alt="SoloVolume icon">

# SoloVolume

A tiny macOS menu bar app that gives a Focusrite Scarlett Solo (or any output with no
hardware volume control) a working volume slider and working keyboard volume keys.

macOS greys out the volume control for interfaces like the Scarlett Solo because the device
doesn't expose one. SoloVolume adds one in software, without installing any audio drivers.

## Features

- Menu bar volume slider and mute
- Keyboard volume and mute keys control the device (Shift+Option for fine steps), with an
  on-screen level indicator
- Keys pass through to macOS as normal when a different output (e.g. AirPods) is in use
- Picks the Scarlett automatically; any other output can be chosen
- Recovers when the device is unplugged and plugged back in
- Launch at login
- Checks for updates once a day and installs them when you agree (signed with SoloVolume's own key)

Requires macOS 14.2 or later. Runs natively on Apple silicon and Intel.

## Install

1. Download the latest `SoloVolume-x.y.dmg` from [Releases](../../releases).
2. Open it and drag **SoloVolume** to **Applications**.
3. Open SoloVolume. It's signed and notarized, so it opens normally.
4. Allow **System Audio Recording** when asked. Without it, audio to the device goes silent.
5. For the volume keys, turn SoloVolume on in **System Settings → Privacy & Security →
   Accessibility** (the app's menu has a shortcut to this).
6. Click the speaker in the menu bar and turn on **Launch at login**.

## How it works

SoloVolume uses Core Audio process taps (macOS 14.2+):

1. A tap captures all audio other apps send to the device and mutes the original.
2. A private aggregate device (the device + the tap) plays that audio back to the device
   with gain applied (cubic taper, ramped per buffer so changes don't click).

The device's own inputs are left closed, so the microphone indicator stays off. If the app
quits, audio goes straight back to the device at **full volume**.

## Privacy

SoloVolume runs entirely on your Mac. It has no accounts, analytics or tracking. It goes
online only for updates: once a day it downloads a small file (`appcast.xml`) from this
repo's GitHub releases to see if there's a new version, and when you install one, the
update itself. Nothing about you or your Mac is sent beyond what any web request carries.

**Audio.** The audio it captures goes straight back out to the device you chose, a few
milliseconds later. It's never saved, recorded or sent anywhere, and only audio headed to
that device is captured; other outputs are left alone. The interface's microphone inputs
are never opened.

**Keys.** The volume-key listener asks macOS only for media-key events (volume, mute and
the like), never ordinary key presses, so SoloVolume can't see what you type. It acts on
volume and mute, and only while the chosen device is your sound output; everything else
passes straight through.

**Permissions.** macOS asks for **System Audio Recording** (to capture and re-play the
audio) and, for the volume keys, **Accessibility**. The only things SoloVolume stores are
its own settings: volume, mute, device and the volume-keys switch.

## Security

- **Signed and notarized.** Releases are signed with Developer ID (team `DHGK36B2V9`) and
  notarized by Apple, and both the app and the `.dmg` carry their notarization ticket.
- **No extra capabilities.** SoloVolume runs with the hardened runtime and asks macOS for
  no entitlements at all. Other apps can't attach to it or slip code into it, so they
  can't borrow the permissions you've given it.
- **Nothing else can drive it.** No URL scheme, AppleScript, Services or network ports; it
  acts only on its menu and your volume keys. It runs no helper programs or scripts and
  uses one outside library (below).
- **Updates that can't be forged.** [Sparkle](https://sparkle-project.org) checks once a
  day over HTTPS. The update feed and every download are signed with SoloVolume's own
  EdDSA key, which isn't on GitHub, and SoloVolume checks both against the key built into
  it before anything is unpacked (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`).
  It won't install an older version. (1.0 and 1.0.1 have no updater; install 1.1 by hand.)
- **One dependency.** Sparkle, pinned to one exact version (2.10.0), whose download SwiftPM
  checks against a fixed checksum. It loads only from inside the app.
- **Releases that can't be swapped.** Releases on this repo can't be changed once
  published, and release tags can't be moved or deleted. Before anything is published,
  `scripts/check-app.sh` checks the app inside the `.dmg` (signature and team on the app
  and Sparkle, hardened runtime, no entitlements, no URL scheme, the pinned update key and
  signed-feed settings, Apple silicon and Intel, notarization), and both signatures are
  checked against the public key users have. Each release lists its `.dmg`'s SHA-256.

SoloVolume isn't sandboxed: process taps and system-wide volume keys aren't available to
sandboxed apps. The protections above are what keep that safe.

To check a download:

```bash
spctl --assess --type open --context context:primary-signature -v SoloVolume-1.1.0.dmg
shasum -a 256 SoloVolume-1.1.0.dmg   # compare with the release notes
```

To report a security problem, see [SECURITY.md](SECURITY.md).

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`). The first build fetches
Sparkle through Swift Package Manager.

```
./build.sh            # builds build/SoloVolume.app
./build.sh --install  # also copies it to /Applications and relaunches it
./build.sh --dmg      # also packages build/SoloVolume-<version>.dmg (notarized)
```

If a "Developer ID Application" certificate is in your keychain, the app is signed with it
(hardened runtime), and `--dmg` also notarizes and staples the app and the disk image using the
notarytool profile `pane-notary` (override with `NOTARY_PROFILE=...`). Create one with
`xcrun notarytool store-credentials <name> --apple-id <email> --team-id <team>`.

Without a Developer ID the build is ad-hoc signed (with library validation relaxed so it
can load Sparkle; `check-app.sh` refuses that for releases), and macOS asks for the audio
and Accessibility permissions again after every rebuild.

Run with `SOLOVOLUME_DIAG=1` to print input levels to stderr once a second.

The icon is drawn by `Icon/make-icon.swift`; run `swift Icon/make-icon.swift` to regenerate it.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Write the notes in `docs/release-notes/<version>.md`.
3. Commit on `main`, then run `./release.sh` (`./release.sh --dry-run` stops before publishing).

It refuses to run with uncommitted changes or a build number that isn't higher than the
last release's, notarizes the app and the `.dmg`, runs `scripts/check-app.sh` on the app
inside the `.dmg`, signs the `.dmg` and the update feed with the Sparkle key in the
keychain (`generate_keys --account SoloVolume`; public half in
`scripts/sparkle-public-key.txt`), checks both signatures, then tags the version and
publishes a GitHub Release with the `.dmg`, `appcast.xml` and the SHA-256. Published
releases are immutable.

The Sparkle private key lives only in this Mac's login keychain. Back it up
(`.build/artifacts/sparkle/Sparkle/bin/generate_keys --account SoloVolume -x <file>`) to
somewhere safe, such as a password manager; without it, no future update can be signed.


## Author

Made by [Jacob Hokanson](https://jlh.ca), who builds web and Mac software in Victoria, BC. More of his apps and tools are at [jlh.ca/tools](https://jlh.ca/tools).

## License

MIT. Not affiliated with Focusrite or Rogue Amoeba.
