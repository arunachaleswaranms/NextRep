# PROJECT_STATE

_Last updated: 2026-10-16. **Latest published release: v1.1.0** (tag
`v1.1.0` on `7e563e2`, PR #14); v1.0.0 before it. The v1.2 roadmap's
Phases 11A–11E are merged (PRs #15–#19). **Phase 11F (v1.2.0 release
qualification) is open on its branch**; the source there is `1.2.0+3`.
`main` is still the merged-development baseline (`af0c883`, version
`1.1.0+2`). **v1.2.0 is a release candidate: NOT tagged, NOT published.**_

| | |
|---|---|
| PUBLISHED | **v1.1.0 (2)** (GitHub Release, signed APK `f6bf2a3a…a2d779`); v1.0.0 before it |
| RELEASE CANDIDATE | **v1.2.0 (3)** on `phase/11f-v1.2-release-qualification`: permanent-key signed candidate `e3847628…de3e2`, reproducible; emulator upgrade rehearsal PASS. See [docs/PHASE_11F.md](docs/PHASE_11F.md) |
| ANDROID PHYSICAL (v1.2.0) | **NOT RUN: awaiting the owner's explicit authorization** to update the official v1.1.0 on the OnePlus CPH2707 (and the phone wasn't connected) |
| PUBLICATION | **NOT AUTHORIZED, NOT PUBLISHED**: no `v1.2.0` tag, no GitHub Release, no uploaded asset |
| STORE SUBMISSION | **NOT APPLICABLE / NOT PLANNED** |

NextRep is distributed as a signed Android APK on GitHub Releases
([docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md)), for personal
use, friends and anyone who finds the public repository, and as source
under the MIT license. Google Play, the App Store and TestFlight are not
planned. TalkBack was deliberately deferred and doesn't block this model.

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public, MIT)
- `main`: `af0c883` (squash merge of PR #19, Phase 11E). Tags `v1.0.0`
  (`b3f9c5c`) and `v1.1.0` (`7e563e2`). PRs #1–#19 are Phases 1–11E.
- Branch: `phase/11f-v1.2-release-qualification`, from `af0c883`
- PR: [#20](https://github.com/arunachaleswaranms/NextRep/pull/20) "Phase
  11F: qualify NextRep v1.2.0 release", **draft**, not merged; CI green on
  `c59a051` (run 38929507633), final head on the PR.
- Author and committer of every commit:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (repo-local
  config). No AI or co-author trailers.

## Phase 11F (v1.2.0 release qualification, branch open)

Record, evidence and gates: [docs/PHASE_11F.md](docs/PHASE_11F.md). No
feature, permission, dependency, schema or backup-format change.

- Version **1.2.0+3** (`appVersion` 1.2.0); package `com.nextrep.nextrep`,
  minSdk 24; schema **v6**; backup write **3** / read 1, 2, 3; signer
  unchanged.
- Release notes [docs/releases/v1.2.0.md](docs/releases/v1.2.0.md); README,
  CHANGELOG, PRIVACY, DIRECT_DISTRIBUTION and a fresh v1.2.0 section in the
  release checklist.
- New `test/app/phase11f_release_test.dart` (17): release identity, the
  platform's installed version, v1.2.0 against a GitHub that lists v1.1.0
  (newer build), v1.2.0 (up to date) or a synthetic v1.3.0 (available /
  not ready), invalid metadata, no request before a tap, backups from this
  build.
- Signed candidate (permanent key, `bc4009f`): `NextRep-v1.2.0-android.apk`,
  66,360,265 bytes, SHA-256
  `e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2`,
  byte-identical across two clean builds.
- Emulator (a disposable API 36 AVD; `emulator-5554` and its official
  v1.1.0 untouched): the published v1.1.0 with real v5 data updated in
  place by the signed candidate; every v5 row identical after v6.

## Phase 11E (integration and regression qualification, merged)

Matrix, evidence and the Phase 11F handoff:
[docs/PHASE_11E.md](docs/PHASE_11E.md). No feature added. Merged as PR #19
(`af0c883`).

- Qualified the merged v1.2 source as one app: core Arc, habits, XP and
  Minimum Day; Smart Hydration; Focus Guard; the manual update check;
  every notification family at once; migrations, backups and restore;
  dates, midnight, time zones and the Android lifecycle; privacy,
  permissions and builds.
- New CI suites in `test/integration/` (104 tests): the cross-feature
  restore on a real SQLite file (worker claim SQL from Kotlin, no HTTP
  client, a restore meeting a held write lock fails as a whole), the real plugin-backed scheduler
  never removing a shown notification of any family, lifecycle and dates
  with everything on, the 34-step combined journey, and a layout sweep of
  the integrated screens. iOS simulator smoke
  `integration_test/phase11e_ios_smoke_test.dart`.
- **One defect, fixed (D1, P2):** Focus Guard's budget row at 2× text on a
  phone broke "Combined daily budget" mid-word for budgets like "1 h 30
  min"; the value now moves under the title at large text. No P0 / P1.
- `flutter test` 1248 / 1248 (1144 + 104); native JVM 67 / 67.
- API 36 emulator (isolated `.qualification` package, official v1.1.0
  byte-identical before and after): natural Focus Guard nudge once a day,
  Hydration delivery, four families together, warm and cold taps, restore,
  reboot, force-stop, revocations, midnight, clock and zone changes, D1
  before / after, one manual check = the only app traffic. iOS builds and
  simulator smokes PASS. Physical device: deferred to Phase 11F.
- Version **1.1.0+2**, schema **v6**, backup format **3**, permissions,
  package and signer: unchanged.

## Phase 11D (About and manual update check, merged)

Contracts and evidence: [docs/PHASE_11D.md](docs/PHASE_11D.md).

- **About NextRep** at `/settings/about`, reachable in every state (History
  tab and standalone Arc History headers, a completed Arc's summary,
  onboarding, setup) and never redirected: identity, **Version / Build from
  the installed package** (`package_info_plus`, not `appVersion`), update
  guidance, privacy, the official repository, open-source licenses.
- **Manual-only check (Android):** one HTTPS GET to
  `api.github.com/repos/arunachaleswaranms/NextRep/releases/latest`, only
  on the user's tap; never at launch, resume, date change, in the
  background, from reminders, Hydration Coach, Focus Guard or restore.
  Single-flight, 10 s total, 256 KiB cap, no redirects, no credentials, no
  retries, nothing persisted. Tested by counting requests through the real
  controller and feed.
- Strict validation: stable `vX.Y.Z` tags only, `draft` / `prerelease`
  false, official `html_url`; the browser page is built from the validated
  version and opened externally only on tap. Newer release without
  `NextRep-vX.Y.Z-android.apk` and `.sha256` uploaded = "not ready yet".
  Distinct states for up to date, update available, newer build, no
  release, network, rate limit, GitHub error and invalid release.
- iOS: no feed is provided; About shows the version and that releases are
  Android only.
- Release permissions: 11C's set **plus `INTERNET`** (manual check only);
  url_launcher's in-app WebView removed. CI and the release script require
  the exact set and still forbid network state, foreground services,
  installs, every-package visibility, overlays, exact alarms, storage,
  media, contacts, accounts, camera and microphone.
- PRIVACY, README and DIRECT_DISTRIBUTION now describe the opt-in check;
  published v1.0.0 / v1.1.0 still have no `INTERNET`.
- Version **1.1.0+2**, schema **v6**, backup format **3**: unchanged.
- `flutter test` 1144 / 1144; native JVM 67 / 67. API 36 emulator:
  zero app traffic until a tap, live check "latest published v1.1.0",
  offline failure and retry, external browser, Focus Guard and Hydration
  Coach offline (isolated `.qualification` package; official v1.1.0
  untouched). iOS simulator run PASS. Physical device: not connected.

## Phase 11C (Focus Guard, merged)

Contracts, architecture and evidence: [docs/PHASE_11C.md](docs/PHASE_11C.md).

- **Focus Guard** (Android), off by default: the user picks apps from a
  launcher-only picker (`MAIN/LAUNCHER` `<queries>`, no
  `QUERY_ALL_PACKAGES`) and sets **one combined daily budget** (default
  60 min). It never blocks apps. Settings at `/settings/focus-guard`; a
  Today card shows `38 / 60 min`, remaining time and Shield strong / Near
  today's limit (≥ 80 %) / Budget reached. Visual only: no XP, streak,
  achievement or Perfect Day effect.
- Usage Access (AppOps) and notifications are separate and both shown.
  Settings are opened only from the user's tap. Today's usage comes from
  `UsageStatsManager.queryEvents` (local midnight → now), access checked
  before and after; unavailable is shown as such, never "0 min". No usage
  is stored.
- **Native WorkManager** job (`focus_guard_check`, unique, periodic
  15 min, KEEP) → a non-exported provider in a separate `:focus_guard`
  process reads Drift's own `nextrep.sqlite` (schema v6) with Android's
  SQLite; the main process never opens the DB natively.
- **One nudge per local day**: the notification is prepared, then the
  day claimed by an atomic, forward-only compare-and-set on
  `focus_guard_preferences.last_nudged_on`, then posted. A claim is never
  given back (an ambiguous `notify` failure keeps it); settings saves
  never overwrite it; denied notifications don't consume the day. Only
  exception: after a full restore, a user who turns Focus Guard on again
  may get a new nudge that day. Channel
  `focus_guard`; tap payload `focus_guard` → Today (home without an
  active Arc).
- Restore keeps apps and budget, leaves Focus Guard off and cancels the
  job. Schema **v6**, backup format **3**, version **1.1.0+2**: unchanged.
- Settings also reachable from Arc History, and from onboarding while it
  is on, so it can always be turned off without an active Arc.
- Qualifying the minified build found a startup crash (R8 full mode
  stripped Room's `WorkDatabase_Impl` constructor); fixed with
  `android/app/proguard-rules.pro`, and CI and the release script now
  check the release dex for it.
- API 36 emulator: 26-step matrix PASS on an isolated `.qualification`
  package (official v1.1.0 untouched), including a natural periodic run,
  one real nudge per day, revocation, reboot, kill, force-stop and day
  rollover. Physical device: deferred (not connected). iOS builds PASS.
- `flutter test` 976 / 976; native JVM tests 67 / 67.
- Release permissions: v1.1.0's plus `PACKAGE_USAGE_STATS` and
  `WAKE_LOCK`; WorkManager's `FOREGROUND_SERVICE`, `ACCESS_NETWORK_STATE`
  and `SystemForegroundService` removed. CI and the release script now
  audit an exact permission allowlist and the merged components.

## Phase 11B (Smart Hydration and v1.2 persistence, merged)

Contracts, algorithm and evidence: [docs/PHASE_11B.md](docs/PHASE_11B.md).

- **Hydration Coach**, off by default, in Reminders: Gentle / Balanced
  (default) / Supportive = up to 3 / 4 / 5 nudges a day; active hours
  08:00 – 20:00 by default, a same-day window of 8 to 18 hours.
- Paces against the Arc's **built-in Water habit** (stable id `water`, any
  title; a custom "Water" never counts) and its effective target per date
  via `DayRules`: revisions, enabled state, Minimum Day. No separate goal.
- Checkpoints `min(mode, target)` from 15 % to 90 % of the window, each
  expecting its share; ±15 min deterministic FNV-1a variation; nudges only
  when behind pace, still ahead and not within 45 min of a Water log.
- One reconciliation plans daily + reflection + hydration; re-run after
  every change to the active Arc. Hydration horizon 7 days: **≤ 63**
  pending. Payload `hydration` → Today; channel `hydration_coach`.
- **Schema v6** (additive v5 → v6) and **backup format 3** (write 3, read
  1 + 2 + 3). Restore turns every reminder, Hydration Coach and Focus Guard
  off. Focus Guard tables and backup shape exist; the feature is Phase 11C.
- Version **1.1.0+2**; release permissions and manifest identical to
  v1.1.0. `flutter test` 902 / 902.
- API 36 emulator: official v1.1.0 updated in place (live v5 → v6), a real
  hydration nudge delivered on time and opening Today, re-planning after
  logs, Minimum Day and Undo as specified. No physical device used.

## Phase 11A (v1.2 foundation and Focus Guard feasibility, merged)

Evidence, contracts and designs: [docs/PHASE_11A.md](docs/PHASE_11A.md).
No product feature, screen, setting, notification or permission.

- **v1.2 scope locked:** Smart Hydration (11B) and About + manual Check for
  updates (11D) guaranteed; Focus Guard (11C) was conditional.
- **FOCUS GUARD: GO.** On the API 36 emulator and the OnePlus (Android 16):
  Usage Access detected, granted and revoked through the real system
  switch; today's usage from UsageStats events (+62 s for a 60 s session,
  live, never backwards); a picker list equal to every launchable app
  (122 / 122) with a narrow `MAIN/LAUNCHER` `<queries>`, without
  `QUERY_ALL_PACKAGES`; WorkManager periodic checks every ~15 minutes
  with no foreground service, exact alarm or battery exemption (31
  overnight runs on the emulator); safe no-op after revocation; reboot
  restores the job; force-stop suspends it until NextRep is opened.
- Android answers usage queries without access with empty data, and
  revocation doesn't restart the app: access is re-checked around every
  query and nothing is cached.
- Platform-neutral foundation in `lib/domain/focus_guard/` and
  `lib/data/focus_guard_codec.dart`, tested with fakes (31 tests); not wired
  into the app, nothing persisted.
- The debug-only probe (separate `.feasibility` package) is in the branch
  history (`2013edd`) and removed (`7120e16`). Release manifest identical to
  v1.1.0.
- Version **1.1.0+2**, schema **v5**, backup write 2 / read 1 + 2: all
  unchanged. Schema v6 and backup format 3 are designed, not built.

## Phase 10D (v1.1.0 release qualification, released)

Evidence: [docs/PHASE_10D.md](docs/PHASE_10D.md). No product feature; one
review correction removed the repository link from share cards and their
caption.

- Version **1.1.0+2** (versionName 1.1.0, versionCode 2). Same application
  id, signing key, schema v5 and backup format 2.
- Release script and CI permission audit also reject media, contacts,
  accounts, camera, microphone and usage-access permissions.
- Signed candidate `NextRep-v1.1.0-android.apk`, 63,684,809 bytes, SHA-256
  `f6bf2a3a5f32a1d53c12d54764361a42f5201ac5d3a60bec2907e15ea2a2d779`,
  byte-identical across clean builds in the fixed local environment.
- Physical: the official v1.0.0 on the OnePlus updated in place
  (`adb install -r`, `firstInstallTime` unchanged, same signer); data
  intact without a restore; backups before and after hold identical data;
  share sheet and WhatsApp picker reached (nothing sent). The corrected
  candidate was installed over the earlier v1.1.0 build (`adb install -r`,
  Success, data intact) and its three cards and share caption re-checked:
  "Made with NextRep" only, no link.
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
  when its history earned each one. Only the **active** Arc's newly
  backfilled catalog achievements may be celebrated, together, once, in one
  card. Completed Arcs are backfilled silently, including the latest
  completed Arc when it is shown as home. A Summit discovered during an
  actual close-out keeps its normal close-out celebration. Idempotent, with no migration flag. Phase 10A's provisional
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
| Version | Published: `1.1.0+2` (versionName 1.1.0, versionCode 2) and 1.0.0 (1). Candidate on the 11F branch: `1.2.0+3` (versionName 1.2.0, versionCode 3) |
| Tag | `v1.0.0` on `b3f9c5c`; `v1.1.0` on `7e563e2`; `v1.2.0` planned, **not created** |
| Android `applicationId` | `com.nextrep.nextrep` (kept for update continuity) |
| Database schema | **v5** in v1.1.0; **v6** since Phase 11B, first released with v1.2.0 |
| Backup | export `formatVersion` **2** in v1.1.0; from Phase 11B (v1.2.0): writes **3**, reads 1, 2 and 3 |
| License | MIT, © 2026 Arunachaleswaran M S |
| Signing certificate | `CN=Arunachaleswaran M S, OU=NextRep`, RSA 4096, valid 2026-10-08 to 2056-09-30 |
| Certificate SHA-256 | `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` |
| v1.0.0 APK | `NextRep-v1.0.0-android.apk`, 63,140,933 bytes, minSdk 24, targetSdk 36 |
| v1.0.0 APK SHA-256 | `03c76da2131d234877e68e9c19f47888b5b7e31a8e639e838e7f9851798c94b9` (reproducible) |
| v1.1.0 candidate | `NextRep-v1.1.0-android.apk`, 63,684,809 bytes, minSdk 24, targetSdk 36 |
| v1.1.0 candidate SHA-256 | `f6bf2a3a5f32a1d53c12d54764361a42f5201ac5d3a60bec2907e15ea2a2d779` (byte-identical across clean builds, fixed environment) |
| Release permissions | v1.1.0: `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; INTERNET, exact-alarm, storage, media, contacts, accounts, camera, microphone and usage-access permissions absent |
| Release permissions (v1.2.0 candidate) | v1.1.0's plus `PACKAGE_USAGE_STATS`, `WAKE_LOCK` (11C) and `INTERNET` (11D, manual update check only): exactly 7, audited on the signed APK |
| v1.2.0 candidate | `NextRep-v1.2.0-android.apk`, 66,360,265 bytes, minSdk 24, targetSdk 36, from `bc4009f` |
| v1.2.0 candidate SHA-256 | `e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2` (byte-identical across two clean builds, fixed environment); **not published** |

The keystore and `android/key.properties` live only on the owner's machine
and are git-ignored. Key rules:
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md). Evidence:
[docs/PHASE_9.md](docs/PHASE_9.md).

## Results

| Gate | v1.2.0 (Phase 11F) | Phase 11D | Phase 11C | Phase 11B | Phase 11A | v1.1.0 (Phase 10D) | Phase 10C | Phase 10B | Phase 10A | v1.0.0 |
|---|---|---|---|---|---|---|---|---|---|---|
| format / analyze | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues | clean / no issues |
| `flutter test` | **1265 / 1265** (+ 67 native JVM) | **1144 / 1144** (+ 67 native JVM) | **976 / 976** (+ 67 native JVM) | 902 / 902 | **800 / 800** | **769 / 769** | 766 / 766 | 693 / 693 | 635 / 635 | 605 / 605 |
| Migrations / backup | 52 / 90 (v6; 1+2+3) | 52 / 90 (v6; 1+2+3) | 52 / 90 (v6; 1+2+3) | 52 / 90 (v6; 1+2+3) | 39 / 76 | 39 / 76 | 39 / 76 | 39 / 71 | 39 / 71 | 39 / 70 |
| APK debug | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| APK release | **PASS, release key, reproducible** (7 permissions) | PASS, 11C's + `INTERNET` | PASS, v1.1.0 + `PACKAGE_USAGE_STATS`, `WAKE_LOCK` | PASS, permissions = v1.1.0 | PASS, permissions = v1.1.0 | **PASS, release key, reproducible** | PASS (local) | PASS (local) | not built | PASS |
| iOS simulator / no-codesign build | PASS / PASS (+ 4 simulator smokes) | PASS / PASS (+ simulator run) | PASS / PASS | PASS / PASS | PASS / PASS | PASS / PASS | PASS (local) | PASS (local) | not run | PASS |
| Signed update continuity (physical, `adb install -r`, same key) | **NOT RUN** (awaiting authorization); emulator rehearsal PASS | n/a (11F) | n/a (11F) | n/a | n/a | **PASS** v1.0.0 → v1.1.0, data kept | n/a | n/a | n/a | **PASS**, data kept |
| Physical smoke | **NOT RUN** (awaiting authorization) | deferred (not connected) | deferred (not connected) | not run | feasibility only (probe package) | **PASS** (incl. share sheet) | n/a | n/a | n/a | **PASS** |

Coverage of handwritten lib: 93.8% at v1.1.0 (93.3% at v1.0.0).
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

1. Decide on the **physical signed upgrade**: authorize (or not) the
   in-place update of the official v1.1.0 on the OnePlus CPH2707 to the
   signed v1.2.0 candidate, after a fresh v1.1.0 backup
   ([docs/PHASE_11F.md](docs/PHASE_11F.md#ag-publication-approval-gate)).
2. Independent review of the Phase 11F PR, then merge.
3. After merge, separately authorize publication: rebuild on `main`
   (SHA-256 must equal the candidate's), tag `v1.2.0`, publish the full
   GitHub Release with the APK and its `.sha256`, then the
   post-publication checks.
