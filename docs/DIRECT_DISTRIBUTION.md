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

macOS / Linux, with both files in the same folder:

```bash
shasum -a 256 -c NextRep-v1.0.0-android.apk.sha256
# NextRep-v1.0.0-android.apk: OK
```

Windows (PowerShell):

```powershell
Get-FileHash NextRep-v1.0.0-android.apk -Algorithm SHA256
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
apksigner verify --print-certs NextRep-v1.0.0-android.apk
# Signer #1 certificate SHA-256 digest: 65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba
```

Publishing the certificate fingerprint is safe: it identifies the signer
and can't be used to sign anything. The private key, the keystore and its
password are never published.

## How updates stay safe

Android itself checks every update: it only installs a new APK over an
installed app when both are signed with the same certificate. Once NextRep
v1.0.0 is installed, Android refuses any "update" that isn't signed with
the NextRep release key, so a tampered APK can't replace your install or
read its data.

Because every release uses the same key, a newer official APK installs
over the old one and keeps your data. You don't need to uninstall.

If Android ever says an update conflicts with the installed app or that the
package is invalid, **don't uninstall to force it.** That means the APK
wasn't signed with the NextRep key. Get the APK from the Releases page
again and check its checksum and certificate.

## Installing and updating

See the README: [Install on Android](../README.md#install-on-android) and
[Updating](../README.md#updating).

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
   builds are reproducible: the same commit and key always give the same
   SHA-256.
3. Create the tag `v<version>` and a GitHub Release from
   `docs/releases/v<version>.md`. Attach the two staged files, and nothing
   else.

The release key and its backups are covered in
[ANDROID_SIGNING.md](ANDROID_SIGNING.md#the-nextrep-release-signing-key-is-critical).
