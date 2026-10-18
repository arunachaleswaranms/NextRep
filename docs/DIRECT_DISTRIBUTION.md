# Direct distribution

NextRep for Android is distributed as an APK on this repository's
[GitHub Releases](https://github.com/arunachaleswaranms/NextRep/releases)
page. It isn't on Google Play or the App Store, and there are no plans for
that.

## Where official APKs come from

Official NextRep APKs are published **only** as assets of a GitHub Release
in `github.com/arunachaleswaranms/NextRep`. Each release has two assets:

- `NextRep-v<version>-android.apk`: the app
- `NextRep-v<version>-android.apk.sha256`: its SHA-256 checksum

A NextRep APK from anywhere else (a mirror, a chat message, an "APK site")
is not an official build. Don't install it.

## Checking a download

### 1. Checksum

The checksum shows that the file you downloaded is the file that was
published, and wasn't damaged or swapped on the way.

macOS / Linux, with both files in the same folder (for example
`<version>` = `1.2.0`):

```bash
shasum -a 256 -c NextRep-v<version>-android.apk.sha256
# NextRep-v<version>-android.apk: OK
```

Windows (PowerShell):

```powershell
Get-FileHash NextRep-v<version>-android.apk -Algorithm SHA256
```

Compare the hash with the one in the `.sha256` file and in the release
notes.

### 2. Signing certificate

Every official NextRep APK is signed with the same release certificate:

```
SHA-256: 65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:
         46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA
Subject: CN=Arunachaleswaran M S, OU=NextRep
```

With the Android SDK build-tools installed you can check it:

```bash
apksigner verify --print-certs NextRep-v<version>-android.apk
# Signer #1 certificate SHA-256 digest: 65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba
```

Publishing the certificate fingerprint is safe: it identifies the signer
and can't be used to sign anything. The private key, the keystore and its
password are never published.

## How updates stay safe

Android itself checks every update: it only installs a new APK over an
installed app when both are signed with the same certificate. Once an
official NextRep is installed, Android refuses any "update" that isn't
signed with the NextRep release key, so a tampered APK can't replace your
install or read its data.

Because every release uses the same key, a newer official APK installs
over the old one and keeps your data (for example v1.2.0 over v1.1.0). You
don't need to uninstall. Exporting a backup first is still a good habit.

If Android ever says an update conflicts with the installed app or that the
package is invalid, **don't uninstall to force it.** That means the APK
wasn't signed with the NextRep key. Get the APK from the Releases page
again and check its checksum and certificate.

## Installing and updating

See the README: [Install on Android](../README.md#install-on-android) and
[Updating](../README.md#updating).

## Checking for updates from the app

v1.0.0 and v1.1.0 can't check for updates: watch the Releases page
instead. From v1.2.0, **About NextRep** on Android has a **Check for
updates** button. It only reads release information; it never downloads or
installs anything:

- It runs only when tapped: never at startup, on resume or in the
  background. Each tap is one HTTPS request to GitHub's "latest release"
  API for this repository
  (`api.github.com/repos/arunachaleswaranms/NextRep/releases/latest`),
  without credentials. What is and isn't sent: [PRIVACY.md](../PRIVACY.md#checking-for-updates-android).
- GitHub's "latest" is the newest **published full release**: drafts and
  prereleases are never offered. The app also rejects anything whose tag
  isn't a plain `vMAJOR.MINOR.PATCH`, whose `draft` or `prerelease` flag
  isn't `false`, or whose page isn't this repository's, and compares
  versions numerically (`1.10.0` is newer than `1.9.9`).
- A newer release counts as available only once both assets above,
  `NextRep-v<version>-android.apk` and its `.sha256`, are uploaded.
  Before that the app says the release is listed but its Android download
  isn't ready yet.
- **View official release** opens
  `github.com/arunachaleswaranms/NextRep/releases/tag/v<version>` in your
  browser, a page the app builds itself from the checked version. From
  there, download, check and install the APK as described above. The usual
  rules still apply: install over your current app, **never uninstall to
  update**, and stop if Android reports a signing conflict.

The check doesn't replace the checksum and certificate checks: it only
tells you that a release exists.

## Builds you make yourself

A build from source is signed with your own debug or release key, not the
NextRep key (see [ANDROID_SIGNING.md](ANDROID_SIGNING.md#building-your-own-copy)).
It can't update an official install, and an official APK can't update it.
Move your data between them with Export Backup and Restore Backup.

## For the maintainer

Release steps, in order:

1. Merge the release PR after review.
2. On `main`, run `tool/release/prepare_android_release.sh` with the release
   key configured. It builds, verifies and stages the APK and its checksum
   in `build/release-candidate/` (git-ignored). `flutter clean` deletes
   that folder, so don't run it until the release is published. Release
   builds have been byte-identical across clean builds of the same commit
   with the same key and toolchain, so the SHA-256 should match the one in
   the release notes. If it doesn't, stop and find out why before
   publishing.
3. Create the annotated tag `v<version>` ("NextRep v<version>") on the
   release commit and a **draft** GitHub Release from
   `docs/releases/v<version>.md`, with its relative links rewritten to
   absolute `https://github.com/arunachaleswaranms/NextRep/blob/v<version>/…`
   URLs (relative links don't resolve on a Release page). Attach the two
   staged files, and nothing else. Download the draft's assets and compare
   them with the staged files before publishing.

Publish the release as a full release (not a draft or prerelease) only once
both files are attached: from v1.2.0, the in-app check reads the
latest published release, and reports a newer one as "not ready yet" until
its APK and checksum are uploaded. Never rename the assets or the tag
format: the check matches `v<version>`, `NextRep-v<version>-android.apk`
and `NextRep-v<version>-android.apk.sha256` exactly.

The release key and its backups are covered in
[ANDROID_SIGNING.md](ANDROID_SIGNING.md#the-nextrep-release-signing-key-is-critical).
