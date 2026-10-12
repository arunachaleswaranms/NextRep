# PROJECT_STATE

_Last updated: 2026-10-12. v1.0.0 is released (tag `v1.0.0` on
`b3f9c5c`, PR #10). Phases 10A (PR #11), 10B (PR #12) and 10C (PR #13,
`901caca`) are merged. Phase 10D (v1.1.0 release qualification) is
complete on its branch; its PR is open and not merged. v1.1.0 is not
tagged or published._

| | |
|---|---|
| RELEASED | **v1.0.0** (GitHub Release, signed APK) |
| RELEASE CANDIDATE | **v1.1.0 (2)**: qualified in Phase 10D, signed APK `3775470e…f00f5`, pending review, merge and publication |
| ANDROID PHYSICAL | **PASS** for v1.1.0: v1.0.0 → v1.1.0 in-place update on the OnePlus CPH2707 (Phase 10D) |
| STORE SUBMISSION | **NOT APPLICABLE / NOT PLANNED** |

NextRep is distributed as a signed Android APK on GitHub Releases
([docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md)), for personal
use, friends and anyone who finds the public repository, and as source
under the MIT license. Google Play, the App Store and TestFlight are not
planned. TalkBack was deliberately deferred and doesn't block this model.

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public, MIT)
- `main`: `901caca` (squash merge of PR #13, Phase 10C). `v1.0.0` is
  tagged on `b3f9c5c` (PR #10). PRs #1–#13 are Phases 1–10C.
- Branch: `phase/10d-v1.1-release-qualification`, from `901caca`
- PR: "Phase 10D: qualify NextRep v1.1.0 release", open for review, not
  merged. No v1.1.0 tag or release.
- Author and committer of every commit:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (repo-local
  config). No AI or co-author trailers.

## Phase 10D (v1.1.0 release qualification, in review)

Evidence: [docs/PHASE_10D.md](docs/PHASE_10D.md). No product change.

- Version **1.1.0+2** (versionName 1.1.0, versionCode 2). Same application
  id, signing key, schema v5 and backup format 2.
- Release script and CI permission audit also reject media, contacts,
  accounts, camera, microphone and usage-access permissions.
- Signed candidate `NextRep-v1.1.0-android.apk`, 63,684,809 bytes, SHA-256
  `3775470e9b461ca8f151b4698ed2dc4c543ef9acb9c95f03932cf2e6647f00f5`,
  byte-identical across clean builds in the fixed local environment.
- Physical: the official v1.0.0 on the OnePlus updated in place
  (`adb install -r`, `firstInstallTime` unchanged, same signer); data
  intact without a restore; backups before and after hold identical data;
  share sheet and WhatsApp picker reached (nothing sent).
- Emulator: backfill on a real v1.0.0 → v1.1.0 update (one combined
  celebration, completed Arc silent, historical dates, XP unchanged),
  templates in setup, Minimum Day return.
- PRIVACY.md covers share cards; release notes in
  [docs/releases/v1.1.0.md](docs/releases/v1.1.0.md).

## Phase 10C (v1.1, merged)

Evidence and rules: [docs/PHASE_10C.md](docs/PHASE_10C.md).

- **Six optional templates**: Hair Care, Skin Care, Eat Fruit, Nuts /
  Seeds, Stretch / Mobility and Reading. They have stable ids and their
  own icons and accents. They aren't starters. They're added only during
  setup, through the existing template path; a running Arc never gains a
  habit.
- **32 achievements** (15 before) in six categories: Progress,
  Consistency, Resilience, Habit Mastery, Reflection and Journey. New:
  14 / 30 / 50-day streaks, 25 Perfect Days, 7 Minimum Days, 14 / 30
  reflections, Day 14 / 60 / 75, and activity mastery keyed off built-in
  habit ids (No Junk Food runs; Workout, Water and Learning totals; Sleep
  Before). Still 0 XP.
- **Backfill:** the first achievement sync of an app session (and after a
  restore) reconciles every started Arc against the full catalog, dated
  when its history earned each one. The home Arc's additions are
  celebrated together in one card; completed Arcs are filled in silently.
  Idempotent, with no migration flag. Phase 10A's provisional
  current-day unlocks hold for all 32.
- The Achievements screen is grouped under category headings.
- A v1.1 backup holding a new unlock can't be restored into v1.0, whose
  validator rejects unknown keys (an existing rule). v1.0 backups restore
  on v1.1.

## Phase 10B (v1.1, merged)

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
- Water / social-media reminders are v1.2 planning.

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
| Version | `1.1.0+2`: versionName 1.1.0, versionCode 2 (Phase 10D). Released: 1.0.0 (1) |
| Tag | `v1.0.0` on `b3f9c5c`; `v1.1.0` planned, not created |
| Android `applicationId` | `com.nextrep.nextrep` (kept for update continuity) |
| Database schema | **v5** (unchanged through v1.1.0) |
| Backup | export `formatVersion` **2**; import reads 1 and 2 (unchanged through v1.1.0) |
| License | MIT, © 2026 Arunachaleswaran M S |
| Signing certificate | `CN=Arunachaleswaran M S, OU=NextRep`, RSA 4096, valid 2026-10-08 to 2056-09-30 |
| Certificate SHA-256 | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |
| v1.0.0 APK | `NextRep-v1.0.0-android.apk`, 63,140,933 bytes, minSdk 24, targetSdk 36 |
| v1.0.0 APK SHA-256 | `03c76da2131d234877e68e9c19f47888b5b7e31a8e639e838e7f9851798c94b9` (reproducible) |
| v1.1.0 candidate | `NextRep-v1.1.0-android.apk`, 63,684,809 bytes, minSdk 24, targetSdk 36 |
| v1.1.0 candidate SHA-256 | `3775470e9b461ca8f151b4698ed2dc4c543ef9acb9c95f03932cf2e6647f00f5` (byte-identical across clean builds, fixed environment) |
| Release permissions | `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (unchanged in v1.1.0). INTERNET, exact-alarm, storage, media, contacts, accounts, camera, microphone and usage-access permissions absent |

The keystore and `android/key.properties` live only on the owner's machine
and are git-ignored. Key rules:
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md). Evidence:
[docs/PHASE_9.md](docs/PHASE_9.md).

## Results

| Gate | v1.1.0 (Phase 10D) | Phase 10C | Phase 10B | Phase 10A | v1.0.0 |
|---|---|---|---|---|---|
| format / analyze | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues |
| `flutter test` | **768 / 768** | 766 / 766 | 693 / 693 | 635 / 635 | 605 / 605 |
| Migrations / backup 1+2 | 39 / 76 | 39 / 76 | 39 / 71 | 39 / 71 | 39 / 70 |
| APK debug | PASS | PASS | PASS | PASS | PASS |
| APK release | **PASS, release key, reproducible** | PASS (local) | PASS (local) | not built | PASS |
| iOS simulator / no-codesign build | PASS / PASS | PASS (local) | PASS (local) | not run | PASS |
| Signed update continuity (physical, `adb install -r`, same key) | **PASS** v1.0.0 → v1.1.0, data kept | n/a | n/a | n/a | **PASS**, data kept |
| Physical smoke | **PASS** (incl. share sheet) | n/a | n/a | n/a | **PASS** |

Coverage of handwritten lib: 93.9% at v1.1.0 (93.3% at v1.0.0).
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
  - Phase 10D ([evidence](docs/PHASE_10D.md#physical-android)): the
    v1.0.0 → v1.1.0 in-place update, data survival, share cards and the
    system share sheet, backups before and after, 2× text and reduced
    motion.
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

1. Independent review of the Phase 10D PR, then merge.
2. On `main`: `flutter clean`, `tool/release/prepare_android_release.sh`,
   and confirm the SHA-256 is `3775470e…f00f5`.
3. Tag `v1.1.0` and publish the GitHub Release from
   [docs/releases/v1.1.0.md](docs/releases/v1.1.0.md) with the APK and its
   `.sha256` file. Nothing for v1.1.0 is tagged or published yet.
