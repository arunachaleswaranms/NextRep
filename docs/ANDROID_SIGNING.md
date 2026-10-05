# Android release signing

**Status: ANDROID STORE SIGNING — NOT YET QUALIFIED.** No production upload
key exists for NextRep yet. Until one is configured, `flutter build apk
--release` and `flutter build appbundle --release` are signed with the local
**debug** key. Those builds install and run, but Google Play rejects them, and
they must not be distributed.

## How signing is wired

`android/app/build.gradle.kts` reads `android/key.properties` when it exists:

- **Present:** release builds use the upload key it names.
- **Absent** (this repository, CI): release builds fall back to the debug
  key, so `flutter run --release` and CI compile checks still work.

`android/key.properties`, `*.jks` and `*.keystore` are git-ignored (root
`.gitignore` and `android/.gitignore`). The repository only contains the
placeholder template `android/key.properties.example`.

## One-time setup (owner only)

Use Play App Signing: Google holds the app signing key, and you keep an
**upload key**.

1. Create the upload keystore **outside the repository**, and back it up
   somewhere safe (a password manager or an offline copy):

   ```bash
   keytool -genkeypair -v \
     -keystore ~/keys/nextrep-upload.jks \
     -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Create `android/key.properties` (git-ignored) from the template:

   ```properties
   storePassword=…
   keyPassword=…
   keyAlias=upload
   storeFile=/Users/<you>/keys/nextrep-upload.jks
   ```

3. Confirm the production `applicationId` first. It is permanent once the
   app is published; see the identifier section in
   [STORE_READINESS.md](STORE_READINESS.md).

4. Build and verify the signature:

   ```bash
   flutter build appbundle --release
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```

   The certificate printed must be your upload key, not
   `CN=Android Debug`.

5. In Play Console, enrol in Play App Signing and upload the AAB.

## Rules

- Never commit `key.properties`, a keystore, or any password.
- Never add signing secrets to GitHub Actions. CI builds release APKs only
  as an unsigned-for-store compile check (debug key) and audits their
  permissions. Store uploads are made from the owner's machine.
- If the upload key is lost, Play App Signing lets you reset it through
  Play Console support. The app signing key itself stays with Google.

## Code shrinking

Flutter's Gradle plugin enables R8 code shrinking and resource shrinking for
release builds. `android/app/src/main/res/raw/keep.xml` keeps the
notification icon, which is looked up by name at runtime. Release builds are
qualified with the plugins' own consumer rules: the reminders and the
document picker run in release builds on the emulator. No extra ProGuard
rules or Dart obfuscation are configured. Turning on `--obfuscate` would
need its symbol files kept per release, so it is deliberately off.
