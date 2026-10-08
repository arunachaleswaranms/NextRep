# PROJECT_STATE

_Last updated: 2026-10-08. Phase 8.5 merged (PR #9). Phase 9 (GitHub
release and self-distribution) is complete on its branch; its PR is open
and not merged._

| | |
|---|---|
| SOFTWARE | **v1.0.0 RELEASE CANDIDATE** |
| ANDROID PHYSICAL | **PASS** (functional, Phase 8.5; signed v1.0.0 and update continuity, Phase 9) |
| DIRECT DISTRIBUTION | **READY FOR OWNER RELEASE APPROVAL** |
| STORE SUBMISSION | **NOT APPLICABLE / NOT PLANNED** |

NextRep is distributed as a signed Android APK on GitHub Releases
([docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md)), for personal
use, friends and anyone who finds the public repository, and as source
under the MIT license. Google Play, the App Store and TestFlight are not
planned. TalkBack was deliberately deferred and doesn't block this model.

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public, MIT)
- `main` baseline: `78f78ef` (squash merge of PR #9, Phase 8.5). PRs #1–#9
  are Phases 1–8.5.
- Branch: `phase/9-github-release-and-self-distribution`, from `78f78ef`
- PR: #10 (https://github.com/arunachaleswaranms/NextRep/pull/10), open for
  review, not merged. No `v1.0.0` tag, no GitHub Release.
- Phase 9 CI: Flutter CI run 37811403687 on `b1aeb05`: **green** (Format,
  analyze and test; Android builds and permission audit). Later commits
  are docs only.
- Author and committer of every commit:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (repo-local
  config). No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on
  PATH)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`;
  `apksigner` and `aapt2` from build-tools 36.0.0
- Physical Android: OnePlus CPH2707, Android 16 (API 36), wireless adb
- Emulator: AVD `RideLink_API36` → `emulator-5554`
- iOS: Xcode 27 beta, Swift Package Manager, iPhone 17 simulator (iOS 27)
- Integration tests: always pass `--no-uninstall`

## Release

| | |
|---|---|
| Version | `1.0.0+1`: versionName 1.0.0, versionCode 1 |
| Planned tag | `v1.0.0` (**not created**) |
| Android `applicationId` | `com.nextrep.nextrep` (kept for update continuity) |
| Database schema | **v5** (unchanged) |
| Backup | export `formatVersion` **2**; import reads 1 and 2 (unchanged) |
| License | MIT, © 2026 Arunachaleswaran M S |
| Signing certificate | `CN=Arunachaleswaran M S, OU=NextRep`, RSA 4096, valid 2026-10-08 to 2056-09-30 |
| Certificate SHA-256 | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |
| Candidate APK | `NextRep-v1.0.0-android.apk`, 63,140,933 bytes, minSdk 24, targetSdk 36 |
| Candidate SHA-256 | `03c76da2131d234877e68e9c19f47888b5b7e31a8e639e838e7f9851798c94b9` (reproducible) |
| Release permissions | `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. INTERNET, exact-alarm and storage permissions absent |

The keystore and `android/key.properties` live only on the owner's machine
and are git-ignored. Key rules:
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md). Evidence:
[docs/PHASE_9.md](docs/PHASE_9.md).

## Results (final code)

| Gate | Result |
|---|---|
| format / analyze | clean / no issues |
| `flutter test` | **605 / 605** |
| Coverage | **93.3%** handwritten lib (91.8% including `schema_versions.dart`) |
| Migrations / backup 1+2 / release qualification | 39 / 70 / 39 |
| APK debug / release | PASS / PASS (release key, not debug) |
| Signed update continuity (physical, `adb install -r`, same key) | **PASS**, data kept |
| One-time debug → release signing switch (physical) | **PASS**: backup verified, restored, data identical |
| Physical v1.0.0 smoke | **PASS** |

Earlier results: integration 7 / 7 on emulator-5554 and on the iPhone 17
simulator (Phase 8); iOS simulator and no-codesign release builds PASS
(Phase 8).

## Devices

- **Physical Android: PASS.** OnePlus CPH2707, Android 16.
  - Phase 8.5 ([evidence](docs/PHASE_8_5_PHYSICAL_ANDROID.md)): the full
    functional matrix, real notifications, reboot recovery, document-picker
    backups, 2× text, reduced motion and profile performance.
  - Phase 9 ([evidence](docs/PHASE_9.md#physical-android)): the
    release-key v1.0.0 install, signing switch, signed update continuity
    and smoke.
- **TalkBack:** deferred by the owner; not a blocker for direct
  distribution. Onboarding, Arc choice and habit setup were done with
  TalkBack in Phase 8.5; the node tree of every other screen was checked.
- **iOS:** source compatible; simulator builds and integration tests pass.
  No iOS release is planned, so physical iPhone, VoiceOver and Apple
  signing are not needed.

## Store documents

[docs/STORE_READINESS.md](docs/STORE_READINESS.md) and
[docs/STORE_METADATA.md](docs/STORE_METADATA.md) are kept as the Phase 7–8
record. Their open gates (identifiers for store registration, Play feature
graphic, screenshots, Data safety, App Store privacy, a hosted privacy
policy, Play App Signing, Apple signing) are **not current blockers**.

The Android system-backup policy is unchanged (`allowBackup` unset) and is
disclosed in [PRIVACY.md](PRIVACY.md).

## Remaining actions (owner)

1. Independent review of the Phase 9 PR, then merge.
2. Back up the release keystore in two secure places, and copy its password
   from `android/key.properties` into a password manager.
3. On `main`, run `tool/release/prepare_android_release.sh` (expected
   SHA-256 as above). Create the tag `v1.0.0` and publish the GitHub Release
   from `docs/releases/v1.0.0.md` with the APK and its `.sha256` file.
4. On the phone: turn reminders back on if you used them (restoring a
   backup turns them off). Keep or delete the pre-switch backup
   (`Download/nextrep-backup-2026-10-08-pre-v1.0.0-signing.nextrep`, plus a
   copy on the Mac), whichever you prefer.
