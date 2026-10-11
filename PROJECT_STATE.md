# PROJECT_STATE

_Last updated: 2026-10-12. v1.0.0 is released (tag `v1.0.0` on
`b3f9c5c`, PR #10). Phase 10A is merged (PR #11, `ba72cf0`). Phase 10B
(Shareable Cards & Meaningful Motion, toward v1.1.0) is complete on its
branch; its PR is open and not merged._

| | |
|---|---|
| RELEASED | **v1.0.0** (GitHub Release, signed APK) |
| IN PROGRESS | **v1.1.0**: Phase 10A merged; Phase 10B ready for review; 10C not started |
| ANDROID PHYSICAL | **PASS** for v1.0.0 (Phase 8.5 / 9). Phases 10A / 10B are not release candidates and have had no physical run |
| STORE SUBMISSION | **NOT APPLICABLE / NOT PLANNED** |

NextRep is distributed as a signed Android APK on GitHub Releases
([docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md)), for personal
use, friends and anyone who finds the public repository, and as source
under the MIT license. Google Play, the App Store and TestFlight are not
planned. TalkBack was deliberately deferred and doesn't block this model.

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public, MIT)
- `main`: `ba72cf0` (squash merge of PR #11, Phase 10A). `v1.0.0` is
  tagged on `b3f9c5c` (PR #10). PRs #1–#11 are Phases 1–10A.
- Branch: `phase/10b-sharing-motion`, from `ba72cf0`
- PR: "Phase 10B: shareable cards and meaningful motion", open for review,
  not merged. No v1.1 tag or release.
- Author and committer of every commit:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (repo-local
  config). No AI or co-author trailers.

## Phase 10B (v1.1, in review)

Evidence and rules: [docs/PHASE_10B.md](docs/PHASE_10B.md).

- **Share cards**, always started by the user and handed to the system
  share sheet (`share_plus` 13.3.1): Today's Progress and My Arc from a new
  Share progress button on Today, and an unlocked achievement from its new
  detail sheet. Locked achievements can't be shared.
- Every card is a **1080 × 1350 PNG** from a fixed canvas, byte-identical
  on any device or text size. Built from persisted read models; sharing
  writes nothing.
- Today's Progress has non-persisted switches for habit names, XP & level
  and streak. No card ever carries reflections, moods, logged times
  (bedtime), reminder settings or calendar dates.
- The PNG is staged in app-private cache and deleted when the sheet closes;
  no storage, media, contacts or photo permission. Release permissions are
  unchanged from v1.0.0.
- **Motion:** the Minimum Day target change eases instead of snapping
  (keyed to target and mode, not to + / −); the share preview reveals once.
  Both honour reduced motion. Journey and celebrations are unchanged.

## Phase 10A (v1.1, merged)

Evidence and rules: [docs/PHASE_10A.md](docs/PHASE_10A.md).

- **Minimum Day is reversible while it is still today.** There is an Undo
  on the activation snackbar and a confirmed "Return to full targets" on
  the banner. Progress is kept; completion and XP are re-settled by
  `DayRules` (a Perfect Day bonus if every full target is met). Past days
  never change.
- **Today's achievement unlocks are provisional.** One that today's history
  no longer earns is removed; unlocks dated before today, and unknown keys,
  are never removed.
- **Sleep Before Target reads as "Last night's bedtime"**, counted for
  today, with an explanation. Its date semantics are unchanged. Custom
  clock-time habits keep neutral wording.
- Next: Phase 10C (templates, more achievements). Water / social-media
  reminders are v1.2 planning.

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
| Version | `1.0.0+1`: versionName 1.0.0, versionCode 1 (unchanged in Phases 10A / 10B; bumped when v1.1.0 is prepared) |
| Tag | `v1.0.0` on `b3f9c5c` |
| Android `applicationId` | `com.nextrep.nextrep` (kept for update continuity) |
| Database schema | **v5** (unchanged through Phase 10B) |
| Backup | export `formatVersion` **2**; import reads 1 and 2 (unchanged through Phase 10B) |
| License | MIT, © 2026 Arunachaleswaran M S |
| Signing certificate | `CN=Arunachaleswaran M S, OU=NextRep`, RSA 4096, valid 2026-10-08 to 2056-09-30 |
| Certificate SHA-256 | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |
| v1.0.0 APK | `NextRep-v1.0.0-android.apk`, 63,140,933 bytes, minSdk 24, targetSdk 36 |
| v1.0.0 APK SHA-256 | `03c76da2131d234877e68e9c19f47888b5b7e31a8e639e838e7f9851798c94b9` (reproducible) |
| Release permissions | `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. INTERNET, exact-alarm and storage permissions absent |

The keystore and `android/key.properties` live only on the owner's machine
and are git-ignored. Key rules:
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md). Evidence:
[docs/PHASE_9.md](docs/PHASE_9.md).

## Results

| Gate | Phase 10B branch | Phase 10A | v1.0.0 |
|---|---|---|---|
| format / analyze | clean / no issues | clean / no issues | clean / no issues |
| `flutter test` | **693 / 693** | 635 / 635 | 605 / 605 |
| Migrations / backup 1+2 | 39 / 71 | 39 / 71 | 39 / 70 |
| APK debug | PASS | PASS | PASS |
| APK release | PASS (local; not a release candidate) | not built | PASS |
| iOS simulator build | PASS (local) | not run | PASS |
| Signed update continuity (physical, `adb install -r`, same key) | n/a | n/a | **PASS**, data kept |
| Physical v1.0.0 smoke | n/a | n/a | **PASS** |

v1.0.0 coverage was 93.3% of handwritten lib.
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

1. Independent review of the Phase 10B PR, then merge.
2. Phase 10C, then prepare v1.1.0: version bump, release notes, a Share
   cards section in PRIVACY.md (it still describes 1.0.0), signed APK and
   physical qualification, including the share sheet on a real device.
   Nothing for v1.1 is tagged or published yet.
