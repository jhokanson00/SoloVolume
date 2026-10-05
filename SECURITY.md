# Security

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately instead:
**[Report a vulnerability](https://github.com/jhokanson00/SoloVolume/security/advisories/new)**
(or the **Security** tab → **Report a vulnerability**).

Include what you found, how to reproduce it, and your SoloVolume and macOS versions
(SoloVolume's is in Finder → Applications → SoloVolume → Get Info; macOS's in  → About
This Mac). You'll get a reply on the report, and fixes ship as a new release. Say if you'd
like to be credited in the release notes.

## Supported versions

Only the latest release.

## In scope

- Audio leaving SoloVolume other than to the output device you chose: being saved,
  recorded, or sent anywhere.
- SoloVolume opening a device's inputs (its microphones), or seeing keys other than the
  volume and mute keys.
- Anything another program on the same Mac could use to make SoloVolume act for it, or to
  borrow the permissions you've given it.
- Updates: the signed feed and downloads on this repo's releases, and how the app checks them.
- The release scripts.

## How SoloVolume is protected

See [Privacy](README.md#privacy) and [Security](README.md#security) in the README.
