# Phase 10D: NextRep v1.1.0 Release Qualification

## Objective

Take merged Phases 10A, 10B and 10C to a **qualified, permanent-signed
v1.1.0 release candidate**: version bump, release and privacy documents, a
reproducible signed APK, and a real v1.0.0 → v1.1.0 in-place update on a
physical phone.

Release qualification only. **No product feature was added and no app code
changed** beyond the version name. No release-blocking bug was found.

**Result: v1.1.0 RELEASE CANDIDATE: QUALIFIED, READY FOR INDEPENDENT
REVIEW.** Nothing was tagged, uploaded or published.

## Baseline

| | |
|---|---|
| `main` | `901cacaca09cc72b35797a901513f78c2ac8f63d` (PR #13, Phase 10C, merged), clean tree |
| Published | `v1.0.0` GitHub Release (tag on `b3f9c5c`), assets `NextRep-v1.0.0-android.apk` (63,140,933 bytes) and its `.sha256` |
| v1.1.0 | no tag, no GitHub Release |
| `flutter test` | 768 / 768 |

## Release identity

| | |
|---|---|
| `pubspec.yaml` | `version: 1.1.0+2` (`lib/app/app_info.dart` follows; a test keeps them in step) |
| Android | `com.nextrep.nextrep`, versionName **1.1.0**, versionCode **2** (unchanged id) |
| iOS bundle id | `com.nextrep.nextrep` (unchanged) |
| Planned tag | `v1.1.0` (not created) |
| Database schema | **v5** (unchanged; no migration) |
| Backup | export `formatVersion` **2**; import reads 1 and 2 (unchanged) |
| Signer | `CN=Arunachaleswaran M S, OU=NextRep`, SHA-256 `65:B7:0C:D0:96:D1:BB:F2:C0:F5:0E:E0:2F:4B:55:97:46:25:CC:4C:DB:EA:D7:39:22:5F:06:75:AF:C8:F0:BA` (the v1.0.0 key; not rotated) |

### Scope of v1.1.0

- **10A:** Minimum Day reversible the same day (Undo, Return to full
  targets), today's achievement unlocks provisional, Sleep Before Target
  as "Last night's bedtime".
- **10B:** Today's Progress, My Arc and Achievement share cards (1080 ×
  1350 PNG, privacy switches, system share sheet), Minimum Day and share
  preview motion that honours reduced motion.
- **10C:** six optional templates (Hair Care, Skin Care, Eat Fruit, Nuts /
  Seeds, Stretch / Mobility, Reading), 32 achievements in six categories,
  history backfill (completed Arcs silent), still 0 XP.

New templates are available during setup only; a running Arc never gains
a habit. A v1.1 backup holding a new achievement can't be restored into
v1.0 (its validator rejects unknown keys); v1.0 backups restore into v1.1.

## Changes in this phase

- `pubspec.yaml`, `lib/app/app_info.dart`: 1.1.0+2.
- `tool/release/prepare_android_release.sh` and the CI permission audit now
  also fail on `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`,
  `READ_MEDIA_VISUAL_USER_SELECTED`, `READ_CONTACTS`, `WRITE_CONTACTS`,
  `GET_ACCOUNTS`, `CAMERA`, `RECORD_AUDIO` and `PACKAGE_USAGE_STATS`, on top
  of `INTERNET`, exact-alarm and storage permissions.
- Documents: PRIVACY.md (share cards), CHANGELOG 1.1.0,
  [releases/v1.1.0.md](releases/v1.1.0.md), README, DIRECT_DISTRIBUTION
  and ANDROID_SIGNING examples made version-generic, RELEASE_CHECKLIST,
  PROJECT_STATE and this record.

## Automated validation

Flutter 3.47.5 / Dart 3.13.4, JDK 21.0.12, Android build-tools 36.0.0,
Xcode 27.0.

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (251 files, 0 changed) |
| `flutter analyze` | no issues |
| `flutter test` | **768 / 768** |
| `flutter test --coverage` | 768 / 768; **93.9%** of handwritten `lib` (8,392 / 8,940 lines; 92.4% including `schema_versions.dart`). v1.0.0: 93.3% |
| Migrations v1 → v5 (`migration_test`, `_v3`, `_v4`, `_v5`) | **39 / 39** |
| Backup (`backup_format_test`, `backup_v2_test`, `backup_restore_test`, `backup_v2_restore_test`, `phase10c_backup_test`) | **76 / 76** |
| Release qualification (`day_change`, `date_edges`, `phase7_lifecycle`, `phase7_accessibility`) | **39 / 39** |
| Phase 10A (`phase10a_flow`, `achievement_reconciliation`, `phase2_tracking`, `time_before`, `phase3_flow`) | **78 / 78** |
| Phase 10B (`phase10b_flow`, `share_card_data`, `share_card_render`, `arc_labels`) | **62 / 62** |
| Phase 10C (`phase10c_catalog`, `phase10c_achievement_rules`, `phase10c_backfill`, `phase10c_flow`, `phase10c_backup`, `achievement_rules`, `achievement_service`, `achievement_v2`) | **102 / 102** |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS |
| `flutter build ios --simulator` | PASS |
| `flutter build ios --release --no-codesign` | PASS (21.3 MB) |

## Release candidate

Built by `flutter clean` + `tool/release/prepare_android_release.sh` on the
owner's machine with the permanent key from `android/key.properties`
(git-ignored, never printed). The script re-ran format, analyze and the
full suite (768 / 768) before building.

| | |
|---|---|
| File | `build/release-candidate/NextRep-v1.1.0-android.apk` (git-ignored) |
| Size | **63,684,809 bytes** |
| SHA-256 | **`3775470e9b461ca8f151b4698ed2dc4c543ef9acb9c95f03932cf2e6647f00f5`** |
| Checksum file | `NextRep-v1.1.0-android.apk.sha256`, `shasum -a 256 -c` OK |
| Signers (`apksigner verify --print-certs`) | exactly **one**: `CN=Arunachaleswaran M S, OU=NextRep`, `65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba`; **not** `CN=Android Debug` |
| Package (`aapt2 dump badging`) | `com.nextrep.nextrep`, versionCode `2`, versionName `1.1.0`, label `NextRep` |
| SDK | minSdk **24**, targetSdk **36**, compileSdk 36 |

### Permissions (`aapt2 dump permissions`, staged APK)

`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, and the
app-private `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
Identical to v1.0.0.

| Forbidden | |
|---|---|
| `INTERNET` | ABSENT |
| `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` | ABSENT |
| `MANAGE_` / `READ_` / `WRITE_EXTERNAL_STORAGE` | ABSENT |
| `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED` | ABSENT |
| `READ_CONTACTS`, `WRITE_CONTACTS`, `GET_ACCOUNTS` | ABSENT |
| `CAMERA`, `RECORD_AUDIO` | ABSENT |
| `PACKAGE_USAGE_STATS` (usage access) | ABSENT |
| Accessibility service | none declared |

Share cards need no storage or media permission: the PNG goes through the
system share sheet from app-private cache.

### Reproducibility

| Build | Commit | SHA-256 |
|---|---|---|
| A: `flutter clean` + script (with gates) | `0560f20` | `3775470e…f00f5` |
| B: `flutter clean` + script (`SKIP_CHECKS=1`) | `0560f20` | `3775470e…f00f5`, `cmp`: byte-identical |
| Final head: `flutter clean` + script | final PR head (docs only since `0560f20`) | `3775470e…f00f5`, byte-identical (see the PR) |

**Byte-identical across clean builds in the fixed qualified local
environment** (same commit, key, Flutter, JDK and build-tools). This is not
a claim of universal reproducibility. The commits after `0560f20` change
only Markdown, which isn't packaged, so the physically qualified APK is the
same file as the final-head candidate.

## Physical Android

Owner's phone over wireless adb, 12 October 2026. Device identifiers,
network addresses, contacts and the owner's NextRep content (habit names,
reflections, moods, reminder times) are not recorded here.

| | |
|---|---|
| Model | OnePlus **CPH2707** |
| Android | **16**, API **36** |

### Before the update

| | |
|---|---|
| Installed | `com.nextrep.nextrep` **1.0.0 (1)** |
| `firstInstallTime` | 2026-10-08 22:02:50 |
| `lastUpdateTime` | 2026-10-08 22:09:47 |
| Installed APK (pulled with `pm path`) | SHA-256 `03c76da2…94b9`: **byte-identical to the published v1.0.0 asset**; signer `65b70cd0…f0ba` (one signer) |
| Notification permission | not granted; no NextRep alarms scheduled |

Snapshot (Today, Arc History, Insights): one active Rolling Arc (Day 9 of
92, started 4 Oct 2026), 4 habits today, 0 of 4 done, a normal (not
Minimum) day, 75 XP, Level 1, Perfect streak 0 / best 1 / 1 Perfect Day,
consistency 11%, **3 of 15** achievements, 1 reflection, 1 Arc in history.

**Backup first.** In v1.0.0: History → Data & Backup → Export Backup →
system picker → `Download/`, "Backup saved." The file's SHA-256 matched on
the phone and the Mac (`c4c3ea92…1d06`). It is kept on the phone and in a
private folder on the owner's Mac (mode 600), not in the repository.
Inspected with the app's own v1.1 `BackupCodec` and `BackupValidator`,
printing only structure: format 2, appVersion 1.0.0, checksum OK, validator
OK (so the v1.0 file is restorable by v1.1), 1 active `rolling92` Arc, 7
habits (4 enabled today), 6 progress rows, 4 XP rows totalling 75, 1
reflection, 1 past Minimum Day, achievements `first_rep`, `first_perfect`,
`first_reflection` (all 2026-10-04).

### In-place update

`adb install -r build/release-candidate/NextRep-v1.1.0-android.apk` →
**Success**. No `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, no uninstall.

| After | |
|---|---|
| Version | **1.1.0 (2)**, `com.nextrep.nextrep` |
| `firstInstallTime` | 2026-10-08 22:02:50 (**unchanged**) |
| `lastUpdateTime` | 2026-10-12 22:22:01 (**updated**) |
| Signer | same (`signatures:[487b1b9c]`, no past signatures); installed APK byte-identical to the candidate, signer `65b70cd0…f0ba` |

**SIGNED UPDATE CONTINUITY v1.0.0 → v1.1.0: PASS.**

### Data survival

Cold launch (`LaunchState: COLD`, 236 ms) after a force-stop. No
onboarding, no restore. Today, Arc History, Journey and Insights matched
the snapshot exactly: Day 9 of 92, 0 of 4 done, 75 XP, Level 1, streaks,
consistency 11%, 1 reflection. The only change: **3 of 15 → 3 of 32**
achievements (the catalog grew; the 3 unlocks keep their 4 Oct date).

### Achievement backfill on the real upgrade

The owner's 9-day history earns **none** of the 17 new achievements (no
14-day streak, 25 Perfect Days, 7 Minimum Days, Day 14, 7 reflections or
activity totals yet), so nothing was inserted and nothing was celebrated.
That is correct; no progress was manufactured to force one. XP unchanged.

The insert path was qualified on the emulator with the same release APK
(below).

### Smoke (v1.1.0 release key build)

| Check | Result |
|---|---|
| Cold launch, force-stop / relaunch | PASS (COLD 236 ms) |
| Background / resume | PASS (same process, WARM 139 ms) |
| Today | PASS, new Share progress button |
| Journey | PASS |
| Journal | PASS (opened; contents not read) |
| Insights | PASS |
| History, active Arc card | PASS. No completed Arc on the phone, so its Summary isn't reachable |
| Achievements | PASS: six headings (Progress 1/4, Consistency 1/9, Resilience 0/3, Habit Mastery 0/7, Reflection 1/4, Journey 0/5), **32** cards; locked cards aren't buttons |
| Reminders | PASS: opens, both switches off as before the update, no crash; nothing rescheduled |
| Data & Backup | PASS |
| Running Arc gained no habit | PASS: still the same 7 habits, none of the six new template ids |
| Crashes (`logcat` FATAL / `E/flutter`) | none |

### Minimum Day and Sleep copy

- The phone's Today offers "Having a rough day?" (normal day). The owner's
  real day was **not** switched to Minimum Day.
- The owner's sleep habit is the legacy done / not-done `sleep_on_time`
  from an early setup. "Last night's bedtime" applies, by design, only to
  the `sleep_before` clock-time habit, so its neutral copy is correct.
- **Physical visual check PASS; mutation behaviour covered by automated and
  emulator qualification** (below).

### Share cards

| Card | Checked |
|---|---|
| Achievement (Clean Sweep, unlocked) | detail sheet → Share Clean Sweep → preview: badge, title, criterion, "UNLOCKED · DAY 1" (challenge day, no calendar date), no Journal text, no time, 4:5, no clipping |
| Today's Progress | "WINTER ARC · DAY 9 OF 92", 0 / 4 complete, the four habits, Sleep Before as done / not done with no time, Level 1 · 75 XP. No streak shown because the Perfect Day streak and every habit streak are 0 (the honest-streak rule) |
| Privacy switches | habit names off → anonymous dots + "0 of 4 habits complete"; XP & level off → gone from the image and its semantics label; streak switch toggles (no streak value exists to hide on this data; hiding is covered by `share_card_data_test` / `phase10b_flow_test`) |
| My Arc | "MY 92-DAY WINTER ARC · Rolling 92-day Arc", habits with **full** goals (30 min, 10 glasses, Daily goal), Day 1 → Day 92, no Minimum targets, no dates; a long title is ellipsized on the image only |

None of the cards showed reflection text, moods, backup data, reminder
settings, a logged bedtime or device data.

### Real Android share sheet

| | |
|---|---|
| Native chooser | PASS: "Share 1 image", a thumbnail of the card, the caption "Achievement unlocked: Clean Sweep — NextRep…" |
| Two quick taps on Share | **one** chooser on the activity stack |
| Cancel | back in the preview, Share available again, no error |
| WhatsApp (`com.whatsapp`, the app target, not a contact shortcut) | PASS: WhatsApp's "Send to…" picker opened with the image (`ExternalShareAlias`). **Backed out with nothing selected; nothing was sent.** |
| Return to NextRep | PASS, same process, no crash |

Other installed targets (Instagram, Telegram, Signal, Gmail, Messages) were
offered in the chooser but **not opened**: they are not claimed as tested.
No card was sent to anyone.

### Backup after the update

v1.1.0: Data & Backup → Export Backup → picker → `Download/` (renamed so the
pre-update file wasn't overwritten). SHA-256 `0eaa6618…e467` on the phone
and the Mac.

- format **2**, appVersion 1.1.0, checksum OK, validator OK
- compared with the v1.0.0 backup without printing content: the whole
  `data` object (arcs, habits, revisions, day modes, progress, XP,
  reflections, achievements with their dates and timestamps, reminder
  settings) is **identical**. Only `appVersion`, `exportedAt` and
  `checksum` differ.

No destructive restore was done on the phone. Restore is covered by the
backup suites (76 / 76) and by the emulator.

### Accessibility and motion

- **2× text** (`font_scale` 2.0) with **all animator scales 0**: Today
  wraps (no "Le…" truncation), the Achievements screen scrolls to Summit,
  the share preview's switches, Share and Cancel stay reachable; the card
  image keeps its fixed 1080 × 1350 layout by design. Settings restored to
  1.0 afterwards.
- Automated: `phase7_accessibility_test`, `phase10b_flow_test` and
  `phase10c_flow_test` (2× text, reduced motion, semantics).
- **TalkBack: DEFERRED** (not run; not claimed).

## Emulator (`emulator-5554`, Android 16 / API 36)

Disposable data only.

### v1.0.0 → v1.1.0 update with backfill

1. Uninstalled the old test build; installed the **published v1.0.0 APK**.
2. A synthetic v1.0-era backup was generated by
   `tool/screenshots/generate_screenshot_backup.dart` **from the v1.0.0 tag**
   (invented habits and reflections): a completed Seasonal Arc 2025 (joined
   Day 15) and an active Rolling Arc on Day 20. Restored through
   onboarding → Restore from a backup in v1.0.0: 12 of 15 achievements on
   the active Arc, 15 of 15 on the completed one, 1935 XP, Level 8.
3. The same generator from the **v1.1.0 code** gave the oracle: what a
   from-scratch v1.1 history holds.
4. `adb install -r` of the candidate → Success, `firstInstallTime`
   unchanged. Cold launch, recorded:
   - **one** combined celebration, "3 ACHIEVEMENTS UNLOCKED · Clean Week ·
     Rest Rhythm · First Chapter", for the active Arc; it dismissed itself;
     nothing else was celebrated
   - active Arc 12 → **15 of 32**; completed Arc 15 → **26 of 32**, silently
   - 1935 XP, Level 8, streaks and today's progress unchanged
5. Exported a v1.1 backup: every achievement key and `unlockedOn` matched
   the oracle (active: `day_14` 2026-10-06, `sleep_before_14` 2026-10-08,
   `no_junk_7` 2026-10-09; completed: `sleep_before_14`, `no_junk_7`,
   `reflections_14`, `workout_30`, `perfect_25`, `learning_30`, `water_30`,
   `day_60`, `day_75`, `reflections_30`, `minimum_7`, each on its historical
   date). Habits, revisions, day modes, progress, XP and reflections were
   byte-identical to the pre-update backup.

### Minimum Day and Sleep Before

- Sleep Before Target (`sleep_before`): "Last night's bedtime · Goal ·
  before 23:30 · Tap to log it for today's check-in", with the info button.
  The custom "Stretch" habit keeps neutral wording.
- Switch to Minimum Day → minimum targets, "Minimum Day activated · Undo",
  banner "Return to full targets" → confirm dialog → full targets back,
  "Back to full targets", "Having a rough day?" offered again, XP 1935 and
  streaks unchanged.

### New templates (fresh database)

`pm clear`, onboarding → Rolling 92-Day Arc → setup:

- starters unchanged (Workout, Water Intake, Learning / Skills, English
  Practice, No Junk Food, Sleep Before Target, Meditation): **none of the six
  new templates is seeded**
- Add Habit lists Hair Care, Skin Care, Eat Fruit, Nuts / Seeds (done / not
  done, Daily), Stretch / Mobility (10 min, minimum 5), Reading (15 min,
  minimum 5), each with its own icon
- Hair Care added once (then "already added"); adding up to 12 habits
  disables Add Habit: "12 habits is the limit"

## Security and secret audit

- Tracked files: no `*.jks`, `*.keystore`, `*.p12`, `key.properties`,
  `*.apk`, `*.nextrep` (other than the synthetic test fixture), share PNGs
  or device dumps. `android/key.properties` is git-ignored; the tracked
  `key.properties.example` holds placeholders only.
- No password, token or API key in the diff.
- Backups, pulled APKs, screenshots and UI dumps stayed in a scratch folder
  outside the repository, or in the owner's private backup folder.
- Commits: author and committer `Arunachaleswaran M S
  <arunachaleswaranms@gmail.com>`, no AI or co-author trailers.

## CI

Final-head GitHub Actions run: recorded in the PR. CI release APKs are
debug-signed compile and permission checks, not distribution builds.

## Known deferrals

- TalkBack human pass (deferred by the owner; not a blocker).
- Physical iPhone: not available; no iOS artifact is published.
- Third-party share targets other than WhatsApp: offered, not opened.
- Physical Minimum Day mutation and destructive restore: not run on the
  owner's real data; covered by tests and the emulator.
- Adding a habit to a running Arc ("habit exists from" dates), scheduled
  habits, smart water reminders, Focus Guard: later versions.

## Publication status

**NOT TAGGED. NOT PUBLISHED.** No `v1.1.0` tag, no GitHub Release, no
uploaded asset.

## Owner release action

After independent review and merge:

1. On `main`, `flutter clean`, then `tool/release/prepare_android_release.sh`
   with the release key. Confirm the SHA-256 is
   `3775470e9b461ca8f151b4698ed2dc4c543ef9acb9c95f03932cf2e6647f00f5`. If it
   differs, stop and find out why.
2. Create the tag `v1.1.0` and a GitHub Release "NextRep v1.1.0" from
   [releases/v1.1.0.md](releases/v1.1.0.md). Attach
   `NextRep-v1.1.0-android.apk` and `NextRep-v1.1.0-android.apk.sha256`
   only.
