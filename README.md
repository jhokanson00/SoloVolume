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

SoloVolume runs entirely on your Mac and never goes online: no accounts, analytics,
tracking or update checks. It has no network code at all.

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
  uses no third-party code, only macOS's own frameworks.
- **Releases that can't be swapped.** Releases on this repo can't be changed once
  published, and release tags can't be moved or deleted. Before anything is published,
  `check-app.sh` checks the app inside the `.dmg`: signature, team, hardened runtime, no
  entitlements, no URL scheme, Apple silicon and Intel, and notarization. Each release
  lists its `.dmg`'s SHA-256.

SoloVolume isn't sandboxed: process taps and system-wide volume keys aren't available to
sandboxed apps. The protections above are what keep that safe.

To check a download:

```bash
spctl --assess --type open --context context:primary-signature -v SoloVolume-1.0.1.dmg
shasum -a 256 SoloVolume-1.0.1.dmg   # compare with the release notes
```

To report a security problem, see [SECURITY.md](SECURITY.md).

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```
./build.sh            # builds build/SoloVolume.app
./build.sh --install  # also copies it to /Applications and relaunches it
./build.sh --dmg      # also packages build/SoloVolume-<version>.dmg (notarized)
```

If a "Developer ID Application" certificate is in your keychain, the app is signed with it
(hardened runtime), and `--dmg` also notarizes and staples the app and the disk image using the
notarytool profile `pane-notary` (override with `NOTARY_PROFILE=...`). Create one with
`xcrun notarytool store-credentials <name> --apple-id <email> --team-id <team>`.

Without a Developer ID the build is ad-hoc signed, so macOS asks for the audio and
Accessibility permissions again after every rebuild.

Run with `SOLOVOLUME_DIAG=1` to print input levels to stderr once a second.

The icon is drawn by `Icon/make-icon.swift`; run `swift Icon/make-icon.swift` to regenerate it.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Write the notes in `docs/release-notes/<version>.md`.
3. Commit on `main`, then run `./release.sh` (`./release.sh --dry-run` stops before publishing).

It refuses to run with uncommitted changes, notarizes the app and the `.dmg`, runs
`check-app.sh` on the app inside the `.dmg`, then tags the version and publishes a GitHub
Release with the `.dmg` and its SHA-256. Published releases are immutable.

## License

MIT. Not affiliated with Focusrite or Rogue Amoeba.
