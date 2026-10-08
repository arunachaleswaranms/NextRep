# Phase 9: GitHub Release & Self Distribution

## Objective

Take merged `main` to a **signed Android v1.0.0 release candidate** for
distribution as an APK on GitHub Releases, for personal use, friends and
anyone who finds the public repository.

NextRep is not being prepared for Google Play, the App Store or TestFlight.
The Phase 7–8 store gates (Play feature graphic, Data safety, store
screenshots, Play App Signing, Apple signing, a physical iPhone, VoiceOver
and TalkBack) are not blockers for this model. They stay recorded as history
in [STORE_READINESS.md](STORE_READINESS.md).

No product change. Schema stays **v5**, backup export stays **format 2**
(import reads 1 and 2), and no dependency changed.

**Result: v1.0.0 RELEASE CANDIDATE: READY FOR OWNER RELEASE APPROVAL.**
Nothing was tagged, uploaded or published.

## Baseline

| | |
|---|---|
| `main` | `78f78ef` (PR #9, Phase 8.5, merged), clean tree |
| Format / analyze | clean / no issues |
| `flutter test` | 605 / 605 |
| Migrations / backup / release qualification | 39 / 70 / 39 |
| `flutter build apk --release` | PASS (debug-signed: no key existed yet) |
| `pubspec.yaml` | `version: 1.0.0+1`, already the target, so unchanged |
| `LICENSE` | none |
| Release key | none: no `android/key.properties`, no keystore |

## Release identity

| | |
|---|---|
| Version | `1.0.0+1`: versionName **1.0.0**, versionCode **1** |
| Planned tag | `v1.0.0` (not created) |
| Android `applicationId` | **`com.nextrep.nextrep`** (unchanged) |
| Android namespace, iOS bundle id | `com.nextrep.nextrep` (unchanged) |
| APK asset | `NextRep-v1.0.0-android.apk` |
| Checksum asset | `NextRep-v1.0.0-android.apk.sha256` |

The application id was kept on purpose. It's already on the physically
qualified phone, and a new id would make a separate app with no in-place
update path. Store-style renaming no longer applies.

## License

MIT, `Copyright (c) 2026 Arunachaleswaran M S` ([LICENSE](../LICENSE)). The
repository had no license before. Flutter adds the project's license to the
app's bundled notices (`NOTICES.Z`), which is the only APK content this
changed.

## Release signing

With the owner's approval, a permanent self-distribution key was created
**outside the repository**:

| | |
|---|---|
| Keystore | PKCS12, alias `nextrep`, on the owner's machine under `~/keys/` (mode 600) |
| Password | 40 random alphanumeric characters (`openssl rand`), passed to `keytool` through the environment, never printed or put on a command line. Stored only in the git-ignored `android/key.properties` (mode 600), to be copied into the owner's password manager |
| Subject / issuer | `CN=Arunachaleswaran M S, OU=NextRep` (self-signed) |
| Key | RSA 4096, SHA256withRSA |
| Valid | 2026-10-08 to 2056-09-30 (10,950 days) |
| Certificate SHA-256 | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |

`android/key.properties` is ignored (`git status --ignored` shows
`!! android/key.properties`). The Gradle fallback is unchanged: without the
file, release builds are debug-signed, so CI stays secret-free. The key
backup rules are in
[ANDROID_SIGNING.md](ANDROID_SIGNING.md#the-nextrep-release-signing-key-is-critical).

`keytool -printcert -jarfile` reports "Not a signed jar file" for these
APKs. With `minSdk` 24 the build is signed with APK Signature Scheme v2
only, so signatures are checked with `apksigner` (build-tools 36.0.0).

## Reproducible APK

Two clean builds of the same commit first differed only in the APK Signing
Block. The v2 signature was identical. The difference was AGP's
dependency-info block (`0x504b4453`), a dependency list encrypted for Google
Play with random padding, so every build had a new SHA-256. It serves only
Play. `android/app/build.gradle.kts` now sets
`dependenciesInfo { includeInApk = false; includeInBundle = false }`.

After that, three clean builds with the release key were **byte-identical**:
two runs of the release script and the separate rebuild used for the update
test below. The signing block now holds only the v2 signature and verity
padding. The same commit and key always give the same SHA-256.

## Release script

`tool/release/prepare_android_release.sh` (see
[ANDROID_SIGNING.md](ANDROID_SIGNING.md#building-a-signed-release)) checks
the tree is clean and `key.properties` exists, then runs format, analyze and
tests, and builds the release APK. It verifies the build output and then
the staged copy:

- the signer must be the release certificate, not `CN=Android Debug`
- the package, version name and version code must match `pubspec.yaml`
- the forbidden permissions must be absent

It writes the `.sha256` file and checks it. It doesn't read passwords,
create keys, change the version, tag, push or upload.

`flutter clean` deletes `build/`, including `build/release-candidate/`. Run
it before the script, never between staging and publishing.

## Release APK

| | |
|---|---|
| File | `build/release-candidate/NextRep-v1.0.0-android.apk` (git-ignored) |
| Size | 63,140,933 bytes (60.2 MiB) |
| SHA-256 | `03c76da2131d234877e68e9c19f47888b5b7e31a8e639e838e7f9851798c94b9` |
| Signer | `CN=Arunachaleswaran M S, OU=NextRep`, v2 scheme, one signer, **not debug** |
| Package / version | `com.nextrep.nextrep`, `1.0.0` (1), label `NextRep` |
| SDK | `minSdkVersion` 24 (Android 7.0), `targetSdkVersion` 36, compile SDK 36 |
| ABIs | `arm64-v8a`, `armeabi-v7a`, `x86_64` |

### Release permissions (aapt2, staged APK)

`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, and the
app-private `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

| Permission | |
|---|---|
| INTERNET | ABSENT |
| SCHEDULE_EXACT_ALARM | ABSENT |
| USE_EXACT_ALARM | ABSENT |
| MANAGE_EXTERNAL_STORAGE | ABSENT |
| READ_EXTERNAL_STORAGE | ABSENT |
| WRITE_EXTERNAL_STORAGE | ABSENT |

## Physical Android

Device: the Phase 8.5 phone, OnePlus CPH2707, Android 16 (API 36), over
wireless debugging. Date: 8 October 2026. The phone is the owner's own.
Device identifiers, network addresses and the owner's NextRep content are
not recorded here.

### Signing transition

The installed NextRep was the Phase 8.5 build: SHA-256 `4e372f52…`
(matching [PHASE_8_5_PHYSICAL_ANDROID.md](PHASE_8_5_PHYSICAL_ANDROID.md)),
1.0.0 (1), signed `CN=Android Debug`. This one-time switch to the release
key happened before any release was published.

1. `adb install -r` of the candidate was refused, as expected:
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.nextrep.nextrep
   signatures do not match newer version`. The installed app was unchanged.
2. **Backup first.** In the installed app: Data & Backup → Export Backup →
   system picker → `Download/`. The file's SHA-256 was identical on the
   phone and on the owner's Mac. Checked without reading any reflection
   text: canonical JSON, checksum valid, `formatVersion` 2, one active arc,
   with the same arc, achievement and reflection counts as the app showed.
   It is kept on the phone (shared storage, which survives an uninstall)
   and in a private folder on the owner's Mac. It is not in the repository.
3. A fingerprint of the data was recorded from the Arc History card (arc
   dates, level, XP, Perfect Days, best streak, consistency, achievements,
   reflections) and from Today.
4. `adb uninstall com.nextrep.nextrep`, only that package. Then
   `adb install` of the staged candidate: signer `487b1b9c` (release key).
5. First launch showed onboarding, as expected for a fresh install.
   **Restore from a backup** → the picker → the backup. The preview
   matched the counts. Restore.
6. Today, Achievements and the Arc History card matched the fingerprint
   **exactly**. Both reminder switches were off, as designed after a
   restore.
7. Force-stop and cold relaunch: the data was still identical.

**Result: PASS, no data lost.** The backup format doesn't record whether
reminders were on. If the owner used reminders, they need to turn them on
again.

### Signed update continuity

1. In the installed v1.0.0, one count was changed on Today (a +1), so the
   update had something fresh to preserve.
2. `flutter clean` and `flutter build apk --release` with the same key gave
   SHA-256 `03c76da2…`, identical to the staged candidate.
3. `adb install -r` → OxygenOS's install check ("No risks found") →
   Continue → **Success**. `firstInstallTime` was unchanged and
   `lastUpdateTime` moved: an update, not a reinstall. The signer was the
   same. No uninstall.
4. Launch: the +1 and all restored data were intact.

**SIGNED UPDATE CONTINUITY: PASS.** A future release signed with the same
key installs over v1.0.0 and keeps the data.

### v1.0.0 smoke (release-key build)

| Check | Result |
|---|---|
| Cold launch (`am start -W`) | PASS (TotalTime 227–585 ms) |
| Today | PASS |
| Habit completion (+15 XP, streak shown, undo revokes) | PASS |
| Count change (+1 / −1) | PASS |
| timeBefore | Not exercised: the owner's arc has no clock-time habit, and habits can't be added to a running arc. Covered by `time_before_test.dart` and the Phase 8.5 phone run; this phase changed no app code |
| Journey | PASS |
| Journal (opens on today; no entry written into real data) | PASS |
| Insights | PASS |
| History | PASS |
| Data & Backup (export and restore through the picker) | PASS |
| Reminders screen | PASS |
| Force-stop / relaunch | PASS |
| Crashes | none |

The smoke inputs were undone afterwards. The owner's data ended identical to
the pre-Phase-9 fingerprint.

## Quality gates (final code)

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (0 changed) |
| `flutter analyze` | no issues |
| `flutter test` | **605 / 605** |
| `flutter test --coverage` | 93.3% of handwritten `lib` (91.8% including `schema_versions.dart`), unchanged |
| Migrations v1 → v5 | 39 / 39 |
| Backup format 1 + 2 | 70 / 70 |
| Release qualification suite | 39 / 39 |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS, release key, reproducible |

## Documentation

- [README.md](../README.md): rewritten for people who find the repository
  (what NextRep is, features, download, install, update, backup, privacy,
  build from source, license). The developer material follows below it.
- [DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md): where official APKs
  come from, checksum and certificate checks, how updates stay safe.
- [releases/v1.0.0.md](releases/v1.0.0.md): the GitHub Release notes.
- [ANDROID_SIGNING.md](ANDROID_SIGNING.md): the permanent key, its
  fingerprint and the key backup warning.
- [CHANGELOG.md](../CHANGELOG.md): the 1.0.0 entry. The phase history moved
  under "Development history".
- [PRIVACY.md](../PRIVACY.md): scope is the GitHub APKs. The store-contact
  placeholder was replaced with the repository's issues, with a warning not
  to post personal data.
- [STORE_READINESS.md](STORE_READINESS.md),
  [STORE_METADATA.md](STORE_METADATA.md): marked as not current. They are
  kept as history and not rewritten.
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md): a direct-distribution
  section.

## CI

Unchanged and secret-free: format, analyze, migrations, backup, release
qualification, all tests, the debug APK, a release compile and the release
permission audit. CI's release APK is debug-signed. It is a compile and
permission check, **not** the distributed APK. The official APK is built on
the owner's machine with the release key.

## Owner release action

After independent review and merge:

1. On `main`, run `tool/release/prepare_android_release.sh` with the release
   key. The APK is reproducible, so it should give the SHA-256 above.
2. Create the tag `v1.0.0` and a GitHub Release titled "NextRep v1.0.0" from
   [releases/v1.0.0.md](releases/v1.0.0.md). Attach
   `NextRep-v1.0.0-android.apk` and `NextRep-v1.0.0-android.apk.sha256`.
3. Back up the keystore to two secure places, and the password to a
   password manager, before anyone installs the release.
