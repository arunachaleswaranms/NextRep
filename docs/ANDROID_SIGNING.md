# Android release signing

**Status: PERMANENT SELF-DISTRIBUTION KEY CONFIGURED (Phase 9, 2026-10-08).**
Official NextRep APKs, starting with v1.0.0, are signed by one permanent
release key that the owner keeps outside this repository.

| Certificate | Value |
|---|---|
| Subject / issuer | `CN=Arunachaleswaran M S, OU=NextRep` (self-signed) |
| SHA-256 fingerprint | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |
| Key | RSA 4096, SHA256withRSA |
| Valid | 2026-10-08 to 2056-09-30 |

The fingerprint is public by design; it identifies official builds (see
[DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md)). The private key, the
keystore and its password are never published.

NextRep is distributed as an APK on GitHub Releases. Google Play and the
App Store are not planned, so there is no Play upload key or Play App
Signing. Earlier phases planned for them (see the history at the end).

## THE NEXTREP RELEASE SIGNING KEY IS CRITICAL

Android only installs an update over an existing app when both are signed
with the same certificate. If the key is lost, a future APK signed with a
different key **cannot update existing installations**. Every user would
have to uninstall and reinstall, which deletes their app data unless they
export a backup first and restore it afterwards. Nothing can recover a lost
key.

Owner rules:

- Back up the keystore (`nextrep-release.jks`) in **at least two** secure
  places, for example an encrypted drive and a second offline copy.
- Keep the keystore password in a password manager. It is the same for the
  store and the key (PKCS12).
- Never commit the keystore, `key.properties` or the password, and never put
  them in CI.
- Never send the keystore or the private key with an APK release. Only the
  APK and its `.sha256` file are published.
- Keep the certificate fingerprint published (this file,
  [DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md), the release notes), so
  anyone can check an APK.

## How signing is wired

`android/app/build.gradle.kts` reads `android/key.properties` when it
exists:

- **Present** (the owner's machine): release builds are signed with the key
  it names. These are the only builds that are distributed.
- **Absent** (a fresh clone, CI): release builds fall back to the local
  debug key, so `flutter run --release` and CI compile checks keep working.
  Those builds are for development only and are never distributed.

`android/key.properties`, `*.jks` and `*.keystore` are git-ignored (root
`.gitignore` and `android/.gitignore`). The repository only has the
placeholder template `android/key.properties.example`.

On the owner's machine the keystore lives at `~/keys/nextrep-release.jks`
(alias `nextrep`), outside the repository, and `android/key.properties`
(mode 600) points at it.

## Building a signed release

```bash
tool/release/prepare_android_release.sh
```

The script needs a clean tree and `android/key.properties`. It runs the
quality gates and builds the release APK, then checks it with the SDK's
`apksigner` and `aapt2`:

- the signer must be the certificate above, never `CN=Android Debug`
- the package, `versionName` and `versionCode` must match `pubspec.yaml`
- the forbidden permissions must be absent

It then stages `build/release-candidate/NextRep-v<version>-android.apk`
and its `.sha256` file and checks the staged copy again. It never reads the
password, creates keys, tags, pushes or uploads. `flutter clean` deletes
`build/`, including the staged files, so run it before the script and not
afterwards.

Release APKs are byte-reproducible: the same commit and key give the same
SHA-256. `build.gradle.kts` leaves out AGP's Play-only dependency block,
which was encrypted with random padding and changed the hash on every
build.

To check any APK by hand:

```bash
"$ANDROID_HOME"/build-tools/<version>/apksigner verify --print-certs NextRep-v1.0.0-android.apk
```

`keytool -printcert -jarfile` prints "Not a signed jar file" for NextRep
APKs. That's expected: with `minSdk` 24 the build uses APK Signature
Scheme v2 only, which `keytool` doesn't read. Use `apksigner`.

## Building your own copy

If you build NextRep from source for yourself, you don't need this key:

- `flutter build apk --debug` or `flutter build apk --release` without a
  `key.properties` produces a debug-signed APK for your own device.
- To sign with your own key, create one with `keytool -genkeypair`
  (`-keyalg RSA -keysize 4096 -validity 10950`, outside the repository),
  then copy `android/key.properties.example` to `android/key.properties`
  and fill it in. Run the release script with `EXPECTED_CERT_SHA256` set to
  your certificate's fingerprint.

A self-built APK has a different signer, so Android won't install it over
an official NextRep install (or the reverse). Move your data with
**Export Backup**, uninstall, install, then **Restore Backup**.

## Signing transition before v1.0.0 (one time)

Builds made before Phase 9, including the Phase 8.5 physical qualification
build, were signed with the developer debug key. Android refuses to update
those in place with the release key. On the owner's phone the switch was
done once, before v1.0.0: export a backup, uninstall, install v1.0.0,
restore. See [PHASE_9.md](PHASE_9.md#signing-transition). No published
release was ever debug-signed, so no user needs this step.

## Code shrinking

Flutter's Gradle plugin enables R8 code shrinking and resource shrinking for
release builds. `android/app/src/main/res/raw/keep.xml` keeps the
notification icon, which is looked up by name at runtime. Release builds are
qualified with the plugins' own consumer rules: the reminders and the
document picker run in release builds on the emulator and on a physical
phone. No extra ProGuard rules or Dart obfuscation are configured. Turning
on `--obfuscate` would need its symbol files kept per release, so it is
deliberately off.

## History

Phases 7 and 8 planned a Google Play upload key with Play App Signing, and
recorded Android signing as a manual store gate
([STORE_READINESS.md](STORE_READINESS.md)). In Phase 9 the distribution
model changed to GitHub releases, so the permanent self-distribution key
above replaced that plan.
