# Phase 11F: NextRep v1.2.0 release qualification

## A. Objective and scope

Prepare **NextRep v1.2.0** (the v1.2 roadmap: Smart Hydration, Focus
Guard, About and the manual update check, Phases 11A–11E) as a
permanently signed Android release candidate. Verify it automatically, by
build audit and on an emulator, record every result, and stop at the
owner's approval gates.

Release qualification only: **no feature, permission, dependency, schema
or backup-format change**. App code changed only for the version.

Approval gates (from the Phase 11F brief):

| Gate | What | Status |
|---|---|---|
| A | Source preparation and automated qualification | done here |
| B | Permanent-key signed candidate; physical-device qualification with explicit authorization before changing the owner's installation | signed candidate done here; **physical: NOT RUN, no authorization** ([P](#p-physical-oneplus-pre-upgrade-state)) |
| C | Pull request, independent review, owner merge | PR opened; **not merged** |
| D | Final build from merged `main` and public release, after separate authorization | **not started; not authorized** |

Results use **PASS**, **FAIL**, **NOT RUN**, **BLOCKED**, **NOT
APPLICABLE**. Nothing below is prefilled: every PASS has evidence in this
document.

## B. Verified Phase 11E baseline

Checked before any change, on 2026-10-16:

| | |
|---|---|
| `origin/main` | `af0c8839f6c76fad1de3f368d019afffd4093c5e`, "Phase 11E: qualify v1.2 integration and regressions (#19)" |
| Merged | PRs #15 (11A), #16 (11B), #17 (11C), #18 (11D), #19 (11E) |
| Main CI | run [38851894773](https://github.com/arunachaleswaranms/NextRep/actions/runs/38851894773) on `af0c883`: success |
| Published | GitHub Release `v1.1.0` (Latest; full, not draft or prerelease; assets `NextRep-v1.1.0-android.apk` and `.sha256`), and `v1.0.0` |
| v1.2.0 | no tag, no GitHub Release (`git ls-remote --tags`, `gh release list`) |
| Source version | `pubspec.yaml` `1.1.0+2`; `appVersion` `1.1.0` |
| Schema / backup | v6; write 3, read 1, 2, 3 |
| Owner's checkout | `~/labs/NextRep`, branch `phase/11b-smart-hydration`, clean; it holds `android/key.properties`, so all development happened in a separate worktree |

Tooling: Flutter 3.47.5 / Dart 3.13.4, JDK 21.0.12, Android build-tools
36.0.0, Xcode 27.0, macOS host in Asia/Kolkata.

## C. Version bump

| | Before | After |
|---|---|---|
| `pubspec.yaml` | `version: 1.1.0+2` | `version: 1.2.0+3` |
| `lib/app/app_info.dart` | `appVersion = '1.1.0'` | `appVersion = '1.2.0'` |
| Android versionName / versionCode | 1.1.0 / 2 | **1.2.0 / 3** (from `pubspec.yaml` through `flutter.versionName` / `flutter.versionCode`) |
| iOS `CFBundleShortVersionString` / `CFBundleVersion` | 1.1.0 / 2 | **1.2.0 / 3** (built bundles checked) |

Every reference to the old version was reviewed:

- **Real package metadata → updated.** `integration_test/phase11d_about_smoke_test.dart`
  and `integration_test/phase11e_ios_smoke_test.dart` read the installed
  app through `package_info_plus` on the simulator; they now expect
  "Version 1.2.0", "Build 3". The About screen's doc comment example
  follows.
- **"This build" → tied to `pubspec.yaml`.** `phase11d_about_flow_test`'s
  "this build" case fed About the shared fake's default v1.1.0 (2), which
  only matched the source by coincidence. It now takes `pubspec.yaml`'s
  version and build number (`pubspecVersion()` in
  `test/support/updates.dart`) and expects "Version 1.2.0" / "Build 3".
- **A fake installed v1.1.0 → kept on purpose.** The 11D / 11E suites'
  `FakeInstalledAppSource` defaults to an installed v1.1.0 (2) so the
  synthetic GitHub v1.2.0 reads as an update; their purpose needs an older
  installed version. Kept, and documented on the fake.
- **History → kept.** Backup fixtures (`appVersion` 1.0.0), migration
  fixtures, `release_version_test` comparisons, release notes for v1.0.0 /
  v1.1.0 and earlier phase records.

`test/app/phase5_routes_test.dart` ("appVersion matches pubspec.yaml")
keeps the two in step.

## D. Exact source revision

| | |
|---|---|
| Branch | `phase/11f-v1.2-release-qualification` from `af0c883` (worktree `~/labs/NextRep-phase11f`, no `key.properties`) |
| `e02d06c` | chore: bump NextRep to v1.2.0 |
| `bc4009f` | test: qualify v1.2.0 release version and compatibility (**signed candidate source**) |
| Later commits | documentation only (Markdown is not packaged); the final head is rebuilt and compared in [AE](#ae-pr-and-ci-evidence) |

## E. Automated qualification

On `bc4009f` (Flutter 3.47.5):

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | **PASS**: 305 files, 0 changed |
| `flutter analyze` | **PASS**: no issues |
| `flutter test` | **PASS: 1265 / 1265** (1248 at baseline + 17 new; none removed, skipped or weakened) |
| `./gradlew :app:testDebugUnitTest` | **PASS: 67 / 67** (0 failures, errors or skips) |
| Migrations v1 → v6 (CI step) | PASS 52 / 52 |
| Migration v5 → v6 (`migration_v6_test`) | PASS 14 / 14 |
| Backup formats 1, 2, 3 (CI step) | PASS 90 / 90 |
| Focus Guard incl. persistence and flow (CI step) | PASS 104 / 104 |
| Manual update check, network boundary, About, routes (CI step) | PASS 182 / 182 |
| Release qualification: lifecycle, accessibility, dates (CI step) | PASS 39 / 39 |
| Smart Hydration and reminders (planner, service, reminders, 11B flow) | PASS 82 / 82 |
| Arc lifecycle, Seasonal / Rolling, Day 92 → 93 (`arc_lifecycle`, `seasonal_arc`, `participation`, `winter_arc_service`, `winter_arc_session`) | PASS 69 / 69 |
| Habit revisions, XP, streaks, levels, achievements, Minimum Day (11 files) | PASS 125 / 125 |
| Phase 11E integration (`test/integration/`) | PASS 104 / 104: restore 3, notifications 6, lifecycle 7, layouts 87, combined flow 1 |
| Phase 11F release (`test/app/phase11f_release_test.dart`) | PASS 17 / 17 |
| The release script's own gates (twice, in the signing checkout) | format clean, analyze clean, 1265 / 1265 each time |

### Release-specific regression tests (`phase11f_release_test.dart`)

| Brief item | Test |
|---|---|
| A, B | `pubspec.yaml` is `1.2.0+3`; `appVersion` is `1.2.0` |
| C | `PlatformInstalledAppSource` returns the platform's version (`PackageInfo` mocked as 9.8.7 (42), unlike `appVersion`), and 1.2.0 (3) for this APK |
| D | Gradle takes versionName / versionCode from `pubspec.yaml`, `applicationId` `com.nextrep.nextrep`, no `applicationIdSuffix`; the built APK's `versionCode='3'` is checked by `aapt2` ([J](#j-apk-identity-and-version-verification)) |
| E | v1.1.0 < v1.2.0 (version and tag) |
| F | installed 1.2.0, latest v1.2.0 → up to date ("Latest published: v1.2.0") |
| G | installed 1.2.0, latest v1.1.0 → "This build is newer than the latest published release." / "Installed: v1.2.0 · Latest published: v1.1.0" |
| H | synthetic v1.3.0 with both assets → available, page `…/releases/tag/v1.3.0`; missing APK, missing checksum, checksum not uploaded or another release's files → not ready |
| I | drafts, prereleases (v1.2.0 and v1.3.0), `-rc1`, no `v`, string `draft`, missing fields, foreign page → invalid, never up to date or available |
| J | About on this build: no request after 5 minutes open; one request per tap; none afterwards |
| K | an export from this build carries `appVersion` 1.2.0, format 3, validates; v1.0 / v1.1 era files (formats 1, 2) still validate |
| L, M | schema 6; backup write 3, read {1, 2, 3} |
| N | covered by `migration_v6_test` (v1.1 data → v6: Hydration Coach off with defaults, Focus Guard off, 60 min, no apps; saved reminders unchanged) and by the emulator rehearsal ([O](#o-android-emulator-qualification)) |

GitHub is always a counting fake; no test reaches the network; no release
is real.

## F. Android debug build

`flutter build apk --debug` in the worktree: **PASS**.

## G. Android release build (without the key)

`flutter build apk --release` in the worktree (no `key.properties`):
**PASS**, 66,360,261 bytes, signer `CN=Android Debug`
(`5317210b…167d`): a compile and audit artifact, **never distributed or
installed over the official app**. Independent audit
([K](#k-permission-and-component-audit)): all checks PASS.

## H. Signing configuration verification

In the owner's checkout `~/labs/NextRep` (the trusted signing
environment; the worktree never had the key):

- tree clean; detached at `bc4009f` for the build (its own branch
  `phase/11b-smart-hydration` is merged, clean and pushed; restored
  afterwards);
- `android/key.properties` present, mode 600, git-ignored
  (`android/.gitignore:12`), with exactly the keys `storePassword`,
  `keyPassword`, `keyAlias`, `storeFile` (values never printed);
- the keystore it names exists outside the repository (mode 600);
- no key was generated, rotated, copied, uploaded or printed.

The configured certificate was verified through the APK it signs (below).

## I. Official signing certificate verification

`apksigner verify --verbose --print-certs` on the staged APK:

| | |
|---|---|
| Scheme | APK Signature Scheme **v2** (v1, v3, v4 not used; minSdk 24) |
| Signers | exactly **1** |
| DN | `CN=Arunachaleswaran M S, OU=NextRep` (**not** `CN=Android Debug`) |
| SHA-256 | **`65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba`** = the official certificate |

**PASS.**

## J. APK identity and version verification

`aapt2 dump badging`: `package: name='com.nextrep.nextrep'
versionCode='3' versionName='1.2.0'`, `minSdkVersion:'24'`,
`targetSdkVersion:'36'`, compileSdk 36, label `NextRep`, native code
`arm64-v8a`, `armeabi-v7a`, `x86_64`. **PASS.**

## K. Permission and component audit

On the **built** signed APK (`aapt2 dump permissions`, `aapt2 dump
xmltree`), by the release script and again by an independent audit:

Requested, exactly (7): `android.permission.INTERNET`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`,
`PACKAGE_USAGE_STATS`, `WAKE_LOCK`,
`com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. **PASS.**

Absent (each checked): `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
`QUERY_ALL_PACKAGES`, `REQUEST_INSTALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`,
`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `MANAGE_EXTERNAL_STORAGE`,
`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_IMAGES`,
`READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED`,
`READ_CONTACTS`, `WRITE_CONTACTS`, `GET_ACCOUNTS`, `CAMERA`,
`RECORD_AUDIO`. **PASS.**

Components:

| Component | Exported | Notes |
|---|---|---|
| `MainActivity` | yes | launcher |
| `SystemJobService` (WorkManager) | yes | guarded by `BIND_JOB_SERVICE` |
| `DiagnosticsReceiver` (WorkManager), `ProfileInstallReceiver` | yes | guarded by `DUMP` |
| `FocusGuardCheckProvider` | **no** | process `:focus_guard` |
| every other provider, service and receiver (notifications, WorkManager, startup, share, Room) | no | |

No Accessibility, VPN or notification-listener service; no
`SystemForegroundService` / `foregroundServiceType`; no `WebViewActivity`.
**PASS.** The allowlists in `.github/workflows/flutter-ci.yml` and
`tool/release/prepare_android_release.sh` are unchanged.

## L. R8 / minification verification

`apkanalyzer dex packages --defined-only` on the signed APK keeps
`androidx.work.impl.WorkDatabase_Impl <init>()`,
`com.nextrep.nextrep.focusguard.FocusGuardWorker <init>(Context,
WorkerParameters)` and `com.nextrep.nextrep.focusguard.FocusGuardCheckProvider
<init>()`. The minified signed APK starts, runs a natural Focus Guard
check in `:focus_guard` and survives a cold start after the migration
([O](#o-android-emulator-qualification)). **PASS.**

## M. Build reproducibility

Both in `~/labs/NextRep` at `bc4009f`, each after `flutter clean`, with
the full `tool/release/prepare_android_release.sh` (gates included):

| Build | SHA-256 | Size |
|---|---|---|
| 1 | `e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2` | 66,360,265 bytes |
| 2 | `e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2` | 66,360,265 bytes |

`cmp`: **byte-identical. PASS.** Build 1 was copied outside `build/`
before the second `flutter clean`. This holds for the fixed local
environment (same commit, key, Flutter, JDK, build-tools); it is not a
claim of universal reproducibility.

## N. APK byte size and SHA-256

| | |
|---|---|
| File | `build/release-candidate/NextRep-v1.2.0-android.apk` in `~/labs/NextRep` (git-ignored; **not published**) |
| Size | **66,360,265 bytes** |
| SHA-256 | **`e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2`** |
| Checksum file | `NextRep-v1.2.0-android.apk.sha256`; `shasum -a 256 -c`: OK |
| Source | `bc4009f` |

## O. Android emulator qualification

### O1. Device and safety

| | |
|---|---|
| AVD | **`NextRep11F_API36`**, created for this phase from the installed `android-36 google_apis arm64-v8a` image, `emulator-5556`, Android 16 (API 36), 1080 × 2400 at 420 dpi, Asia/Kolkata |
| Data | synthetic only: a backup generated by `tool/screenshots/generate_screenshot_backup.dart` **from the `v1.1.0` tag** (invented habits and reflections) |
| `emulator-5554` | untouched: its official v1.1.0 install was not updated, cleared or uninstalled; nothing was installed on it |
| Owner's phone | untouched (see [P](#p-physical-oneplus-pre-upgrade-state)) |
| Package | the official `com.nextrep.nextrep`: this disposable AVD let the **real signed candidate** be qualified, instead of a debug-signed `.qualification` copy. No temporary package id was used or committed |

`adb root` was used on this AVD only, to copy the app's database for
comparison (the release build isn't debuggable).

### O2. Signed v1.1.0 → v1.2.0 upgrade rehearsal

1. Installed the **published** `NextRep-v1.1.0-android.apk` (downloaded
   from the v1.1.0 release; `shasum -c` OK, 63,684,809 bytes, signer
   `65b70cd0…f0ba`). `firstInstallTime` 2026-10-16 20:42:53.
2. In v1.1.0: onboarding → **Restore from a backup** (the synthetic file):
   a completed Seasonal Arc 2025 and an active Rolling Arc on Day 20.
   Turned the **daily reminder on** (08:00; notification permission
   allowed), left the **evening reflection off** (21:00). Raised Water to
   10 glasses (minimum 4) **from tomorrow** (a habit revision).
3. **Pre-upgrade backup** in v1.1.0 (Data & Backup → Export → Downloads):
   format **2**, appVersion 1.1.0, checksum OK, validator OK (checked with
   the app's own `BackupCodec` / `BackupValidator`, printing counts only);
   SHA-256 `d5c1891c…70ac` identical on the device and the Mac.
4. **v5 database** copied (`user_version` 5, `integrity_check` ok,
   `foreign_key_check` empty): 2 Arcs, 16 habits, 1 revision, 501 progress
   rows, 9 day modes, 563 XP rows (9,510 XP), 41 achievements, 47
   reflections, reminder row `daily on 08:00, reflection off 21:00`; 13
   pending daily-reminder alarms.
5. `adb install -r build/release-candidate/NextRep-v1.2.0-android.apk`
   (no `-d`, no uninstall, no clear) → **Success**.

| After the install | |
|---|---|
| Package / version | `com.nextrep.nextrep` **1.2.0 (3)** |
| `firstInstallTime` | 2026-10-16 20:42:53 (**unchanged**) |
| `lastUpdateTime` | 2026-10-16 20:54:01 |
| Signer | same (`signatures:[487b1b9c]`, no past signatures) |
| Installed APK | SHA-256 `e3847628…de3e2` = the candidate |

6. **Cold launch** (`LaunchState: COLD`, 1,048 ms): no onboarding, no
   crash (`logcat`: no FATAL / `E/flutter`). Today identical to before the
   update: Day 20 of 92, 1935 XP, Level 8 (185 / 250), Perfect streak 1 ·
   best 4 · 14 total, 3 of 6 done, 15 of 32 achievements; History lists
   both Arcs as before.
7. **Real v5 → v6 on the device file:** `user_version` **6**,
   `integrity_check` ok, `foreign_key_check` empty, `journal_mode` delete,
   the two Focus Guard tables added, one `nextrep.sqlite`. **Every v5
   table is identical row for row** (`winter_arc_sessions` 2,
   `habits` 16, `habit_revisions` 1, `daily_habit_progress_entries` 501,
   `day_modes` 9, `xp_transactions` 563, `achievement_unlocks` 41,
   `daily_reflections` 47). The reminder row keeps every v5 value (daily
   on 08:00, reflection off 21:00, same `updated_at`) and gains Hydration
   Coach **off**, 08:00–20:00, Balanced. Focus Guard: no row and no apps,
   so **off, 60 minutes**. Still 13 alarms (the daily reminder), 0 jobs.
   The upgrade was not treated as a restore.
8. **Post-upgrade backup** (format **3**, appVersion 1.2.0, checksum and
   validator OK): `arcs` (every habit, revision, day mode, progress row,
   XP row, achievement and reflection) **identical** to the pre-upgrade
   backup; reminder times identical; added only `hydrationStart` /
   `hydrationEnd` / `hydrationMode` and an empty `focusGuard`. The
   pre-upgrade file was kept (SHA-256 unchanged).

**Signed update continuity and data preservation on the emulator: PASS.**

### O3. Smoke of the signed, minified candidate

| # | Check | Result |
|---|---|---|
| 1 | Installs | PASS (O2) |
| 2 | Launches; cold start | PASS (COLD 918–1,048 ms) |
| 3 | No R8 crash | PASS (`logcat` clean; `:focus_guard` provider and WorkManager ran) |
| 4 | About: Version 1.2.0 · Build 3 | PASS |
| 5–6 | Onboarding; Rolling Arc start | PASS (O4) |
| 7 | Today loads | PASS |
| 8–9 | Complete a habit; XP | PASS: No Junk Food → "+15 XP", 1935 → 1950, 4 of 6 |
| 10 | Journal | PASS: today's reflection edited (mood), saved |
| 11 | Hydration settings open | PASS: off after the update, Balanced; daily on / reflection off kept |
| 12 | Hydration scheduled | PASS: on → +24 alarms (Balanced, 4 × the 6 remaining days; today's window had passed), Supportive +30, Gentle +18; all 37 inexact `RTC_WAKEUP` (window 1 h, no exact alarm), all between 08:00 and 20:00 (17 Oct: 09:53, 12:38, 15:54, 18:39) |
| 13 | Focus Guard settings open | PASS: off after the update; switch disabled until access + an app; Usage Access "Not allowed" explained |
| 14 | Usage Access | PASS: "Allow Usage Access" → system page → switch → `GET_USAGE_STATS: allow`; "Allowed" on return |
| — | Picker | PASS: launcher apps; search "NextRep" → "No apps match your search." (the app itself isn't offered); "Clo" → Clock; 1 chosen · up to 100 |
| — | Budget | PASS: 0 and 1441 → "Enter 1 to 1440 minutes."; 1 saved ("1 min") |
| 15 | Enable | PASS: "On. Checking in the background."; **one** unique WorkManager job; `:focus_guard` process started (the native provider opened the migrated v6 database) |
| — | Measurement | PASS: 80 s in Clock → Today card "1 of 1 minutes used today. Budget reached. Tomorrow is a fresh day." |
| 16 | **Natural** background run | PASS: no forced run. 21:17:28 `WM-WorkerWrapper` started `FocusGuardWorker`, `:focus_guard` unfrozen, "Worker result SUCCESS"; one notification, channel `focus_guard`, tag `focus_guard`, id 1: "You've reached today's 1-minute Focus Guard budget. Time to come back to your Arc?" |
| 17 | Tap routing | PASS: tap → NextRep on Today; only that notification removed |
| — | Reboot (app not opened) | PASS: job back (one), 37 alarms back, no notification |
| — | Second natural run, same day | PASS: 21:32:28 after the reboot, the same unique work id, a fresh `:focus_guard` process opened the v6 database, "Worker result SUCCESS", **no** second notification |
| — | Force-stop / reopen | PASS: force-stop → 0 jobs, 0 alarms, `stopped=true`; opening NextRep → 1 job, 37 alarms |
| 18 | Backup export | PASS: O2 step 8; with Focus Guard configured the file holds only `dailyBudgetMinutes` 1 and the one package name, no enabled state, nudge date or usage; Hydration window and mode included |
| 19 | Backup restore | PASS: the format-3 file (everything on: daily reminder, Hydration Coach, Focus Guard) → two confirmations → data as in the file (1950 XP, 4 of 6); every reminder and Hydration Coach **off** (times, Balanced kept); Focus Guard **Off** with Clock kept; 0 jobs, 0 alarms, 0 notifications, 0 bytes. Then the **format-2** v1.1.0 file → the pre-upgrade state (1935 XP, 3 of 6) |
| 20 | Reopen | PASS: force-stop → cold launch after each restore, same data, no FATAL / `E/flutter` |
| 21 | No HTTP without a tap | see O5 |

### O4. Fresh install

On the same disposable AVD, `pm clear com.nextrep.nextrep` (synthetic data
only; this is never done on the owner's phone), then the signed
candidate cold-started (1,099 ms) on onboarding with **About NextRep**,
**Let's Begin** and **Restore from a backup**; Let's Begin → Rolling 92-Day
→ 4 habits → Start Winter Arc → **Day 1 of 92**, Friday 16 October, 0 XP,
Level 1, 0 of 4. 0 bytes. **PASS.**

### O5. Manual update check (pre-publication)

App UID 10213, `dumpsys netstats --poll`, UID stats (Chrome and the
system have their own UIDs):

| Step | rx / tx bytes |
|---|---|
| Install, cold launch, migration, Today, History | 0 / 0 |
| About opened; left open 20 s | 0 / 0 |
| **One tap** on Check for updates | **9,448 / 1,295** |
| 30 s later | 9,448 / 1,295 (nothing further) |
| After the reboot (counters restart): Focus Guard natural run, WorkManager, export, both restores, force-stop, fresh install, onboarding, Arc start | **0 / 0** |

Result on screen: **"This build is newer than the latest published
release." · "Installed: v1.2.0 · Latest published: v1.1.0"**, the correct
pre-publication answer from the live GitHub API (v1.1.0 is still the
latest release). No APK downloaded (Downloads unchanged), no installer.
"You're using the latest published version" is **not** expected before
publication and is a Gate D check ([AH](#ah-post-publication-verification-checklist)).

## P. Physical OnePlus pre-upgrade state

**NOT RUN — owner authorization not given; device not connected.**

The owner's OnePlus CPH2707 (Android 16), with the official v1.1.0 and
real personal data, was **not touched**. `adb devices -l` at the start of
this phase listed only `emulator-5554`; the phone was not connected over
wireless or USB adb. The brief says that preparing Phase 11F is not
itself authorization to change the production installation, and no such
authorization was given in this phase. No command was sent to the phone.

The authorized procedure is written out in
[AG](#ag-publication-approval-gate) and [AH](#ah-post-publication-verification-checklist),
and the emulator rehearsal ([O](#o-android-emulator-qualification)) ran
it end to end on synthetic data.

## Q. Pre-upgrade backup evidence

**NOT RUN (physical).** No backup was taken from the phone.

Emulator rehearsal: PASS ([O2](#o2-signed-v110--v120-upgrade-rehearsal)).

## R. Signed in-place update evidence

**NOT RUN (physical).** Emulator rehearsal: PASS.

## S. Real database migration evidence

**NOT RUN (physical).** A production database has not met schema v6 on a
phone yet; this remains the release's main untested risk. Emulator
rehearsal (real v1.1.0 → v1.2.0 install, real file): PASS.

## T. User-data preservation comparison

**NOT RUN (physical).** Emulator rehearsal: every v5 table identical row
for row; backups before and after hold identical Arc data. PASS.

## U. Smart Hydration qualification

| Where | Result |
|---|---|
| Automated | PASS (82 / 82, plus Phase 11E notifications and lifecycle) |
| Emulator, signed candidate | PASS for the items in [O3](#o3-smoke-of-the-signed-minified-candidate) |
| Physical | **NOT RUN** (no authorization) |

## V. Focus Guard qualification

| Where | Result |
|---|---|
| Automated | PASS (104 / 104; JVM 67 / 67) |
| Emulator, signed candidate | PASS for the items in [O3](#o3-smoke-of-the-signed-minified-candidate) |
| Physical | **NOT RUN** (no authorization). Android 16 / OxygenOS background behaviour on the phone is not qualified for v1.2.0 |

## W. Notification integration

| Where | Result |
|---|---|
| Automated | PASS (`phase11e_notifications_test` 6 / 6: four channels, disjoint ids, ≤ 63 pending, `cancelAll` never called, routing) |
| Emulator, signed candidate | see [O3](#o3-smoke-of-the-signed-minified-candidate) |
| Physical | **NOT RUN** |

## X. Manual update-check qualification

| Where | Result |
|---|---|
| Automated | PASS: 182 / 182 (11D) and 17 / 17 (11F): F, G, H, I, J above |
| Emulator, signed candidate, live GitHub | PASS ([O5](#o5-manual-update-check-pre-publication)): 0 bytes until the tap; one tap → one exchange (9,448 / 1,295 bytes) → "newer than the latest published v1.1.0"; nothing after; no download, no installer |
| Physical | **NOT RUN** |
| Post-publication "latest published: v1.2.0" | **NOT RUN: Gate D** ([AH](#ah-post-publication-verification-checklist)); not simulated as a live result |

## Y. Backup format-3 qualification

| Check | Result |
|---|---|
| Formats 1, 2, 3 (automated) | PASS 90 / 90; 11E restore 3 / 3; 11F K |
| Device export after the upgrade | PASS: format 3, appVersion 1.2.0, checksum and validator OK, Arc data identical to the v1.1.0 file |
| Hydration settings serialized | PASS: `hydrationStart`, `hydrationEnd`, `hydrationMode` |
| Focus Guard in the file | PASS: `dailyBudgetMinutes` and `selectedApps` only; **no** enabled state, nudge date or usage |
| Restore format 3 / format 2 on the device | PASS (O3 #19): opt-ins off, settings kept, 0 jobs, 0 alarms |
| Physical export | **NOT RUN**; physical restore not planned (it replaces the owner's data) |

## Z. iOS compatibility

| Check | Result |
|---|---|
| `flutter build ios --simulator` | **PASS** |
| `flutter build ios --release --no-codesign` | **PASS** (22.3 MB) |
| Built bundles | `CFBundleShortVersionString` 1.2.0, `CFBundleVersion` 3, `com.nextrep.nextrep`; no entitlements |
| `integration_test/phase11e_ios_smoke_test.dart` (iPhone 17 simulator, iOS 27.0) | **PASS**: Arc, habits, Hydration Coach UI, no Focus Guard, Data & Backup, About **1.2.0 (3)** from the real `Info.plist` without a check, **0** `HttpClient`s |
| `phase11d_about_smoke_test`, `day_one_smoke_test`, `phase7_release_smoke_test` | **PASS / PASS / PASS** ("Version 1.2.0, Build 3, no update check offered") |
| `ios/` changes | none |

No IPA was produced for distribution.

## AA. Security and privacy audit

- Dependencies: `pubspec.lock` unchanged from `af0c883`; no analytics,
  advertising, crash-reporting, remote-config or sync SDK.
- Network: only `lib/data/github_release_feed.dart` (and the URL
  constants in `official_source.dart`) do HTTP; the static boundary test
  passes; no WebView; no token, bearer, API key or credential in `lib/` or
  `android/app/src`.
- Logging: no `print` / `debugPrint` in `lib/`; the worker logs its
  outcome name only in debuggable builds.
- Android: the exact 7-permission set and component audit of the signed
  APK ([K](#k-permission-and-component-audit)); no auto-download or
  installer (no `REQUEST_INSTALL_PACKAGES`).
- iOS: no entitlements, no `Info.plist` change.
- Measured: Focus Guard, Hydration Coach, WorkManager, reboot, backups and
  restores sent 0 bytes on the emulator; the only traffic was the tapped
  check.
- PRIVACY.md, README and the release notes now describe 1.2.0 as built,
  including that the GitHub request is **not anonymous** (IP address).
- Repository: no keystore, `key.properties`, password, token, APK,
  `.sha256`, personal backup, device database or dump is tracked; the two
  tracked `.nextrep` files are the synthetic test fixtures. Emulator
  backups, database copies and APK evidence stayed in a scratch folder
  outside the repository.
- Commits: author and committer `Arunachaleswaran M S
  <arunachaleswaranms@gmail.com>`, no AI or co-author trailers.

**PASS.**

## AB. Confirmed defects and fixes

**None.** No P0, P1, P2 or P3 defect was found. No product code changed
besides the version, so no fix commit exists.

Investigated, not defects:

- `flutter analyze` and `dart format` flagged the new test file once
  (unused import, formatting) before its commit; fixed in the test.
- `./gradlew` is absent in a fresh worktree until the first Flutter
  Android build generates it (git-ignored).
- The document picker can show a file renamed from the shell under its old
  name (MediaStore cache), an emulator artifact.

## AC. Known limitations

- **Physical device not qualified for v1.2.0** (no authorization). The
  first real production database to meet schema v6 on a phone, and Focus
  Guard / Hydration Coach under OxygenOS background limits, are untested.
- Hydration Coach delivery was not re-observed on the signed candidate (it
  was scheduled and checked); delivery and taps were qualified on the
  minified build in Phase 11E (E12, E13). Timing is best effort.
- Focus Guard checks are best effort (Doze, standby buckets, Android 16
  flexibility); the emulator's two natural runs were 15 minutes apart.
- Reproducibility is shown for one fixed local environment.
- Human TalkBack / VoiceOver passes: not run (unchanged, non-blocking).

## AD. Final release checklist

The fresh v1.2.0 record is in
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md#direct-distribution-v120-phase-11f).
Items are ticked only where this document has evidence; the physical,
review, merge and publication items stay open.

## AE. PR and CI evidence

Filled in after the PR is opened: PR URL, final head SHA, CI run and
conclusion for both jobs, and the final-head signed rebuild's SHA-256.

## AF. Post-merge rebuild requirements

1. `git fetch origin`; Phase 11F PR merged; `main` CI green.
2. On the owner's checkout: `git switch main && git pull --ff-only`;
   `HEAD` is the merge commit; `pubspec.yaml` `1.2.0+3`, `appVersion`
   `1.2.0`; `git status` clean.
3. `android/key.properties` present (never printed).
4. `flutter clean`, then `tool/release/prepare_android_release.sh`.
5. Signer `65b70cd0…f0ba`, `com.nextrep.nextrep` 1.2.0 (3), the 7
   permissions, components and R8 constructors (the script), plus
   `shasum -a 256 -c`.
6. The SHA-256 **must equal**
   `e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2`.
   The squash merge holds the same packaged source as `bc4009f` (only
   Markdown changed after it), so the same toolchain must give the same
   bytes. If it differs: **stop**, compare the trees, and repeat the
   affected device qualification on the new APK.
7. Release notes match that exact file (size, SHA-256).

## AG. Publication approval gate

Two separate owner decisions remain, in this order.

**1. Physical signed upgrade (Gate B, not yet authorized).** If the owner
authorizes it, on the OnePlus CPH2707 only, by explicit serial:

1. Connect the phone; confirm serial, `ro.product.manufacturer`
   OnePlus, `ro.product.model` CPH2707, Android 16, not an emulator.
2. Record `com.nextrep.nextrep` versionName 1.1.0, versionCode 2, signer
   `65b70cd0…f0ba` (installed APK pulled and checked), `firstInstallTime`,
   `lastUpdateTime`.
3. In v1.1.0: Data & Backup → **Export Backup** (format 2); copy it off the
   phone to a private folder; checksum and validator check with
   `backup_check` (counts only). **No valid backup → stop.**
4. `adb -s <serial> install -r build/release-candidate/NextRep-v1.2.0-android.apk`
   (never `-d`, never uninstall, never `pm clear`). Failure → stop and
   inspect; never uninstall to fix it.
5. Verify 1.2.0 (3), same signer, `firstInstallTime` unchanged; cold
   launch; compare with the backup; export a format-3 backup and compare
   (as in [O2](#o2-signed-v110--v120-upgrade-rehearsal)); Hydration Coach
   and Focus Guard off; reminders as before.
6. Smoke, notifications, About (one tap → "newer than v1.1.0"), per-UID
   bytes; Hydration Coach and Focus Guard only as authorized, restored
   afterwards. No restore on the phone.

**2. Publication (Gate D, not authorized).** Only after review, merge,
[AF](#af-post-merge-rebuild-requirements) and an explicit "publish v1.2.0":

- `v1.2.0` tag and release absent; tag the release commit;
- create the release **as a draft**, attach exactly
  `NextRep-v1.2.0-android.apk` and `NextRep-v1.2.0-android.apk.sha256`,
  notes from [releases/v1.2.0.md](releases/v1.2.0.md); then publish it as
  a **full** release (not prerelease);
- never rename the assets, never a second tag, never move a published tag.

## AH. Post-publication verification checklist

- [ ] Release `v1.2.0` exists on the intended commit; full, not draft or
      prerelease; both assets uploaded with the exact names and sizes
- [ ] Downloaded APK: SHA-256 `e3847628…de3e2`, signer `65b70cd0…f0ba`
- [ ] `api.github.com/repos/arunachaleswaranms/NextRep/releases/latest`:
      `tag_name` `v1.2.0`, `draft` false, `prerelease` false, both assets
- [ ] On the upgraded v1.2.0 app: About shows 1.2.0 (3); 0 bytes before the
      tap; one tap → one request → "You're using the latest published
      version." / "Latest published: v1.2.0"
- [ ] The release is listed on the Releases page; README / PROJECT_STATE /
      CHANGELOG updated to "released"
- [ ] (A v1.1.0 install can't check: it has no update checker.)

## AI. Final qualification verdict

| Gate | Result |
|---|---|
| Baseline (main, CI, release state, no v1.2.0) | PASS |
| Version bump 1.2.0+3 / `appVersion` 1.2.0 | PASS |
| Format / analyze / `flutter test` / JVM | PASS (0 changed / no issues / 1265 / 67) |
| Focused suites (migrations, backups, Focus Guard, update check, hydration, Arc, XP, 11E, 11F) | PASS |
| Android debug / release build (no key) | PASS / PASS |
| Signed candidate (permanent key, script) | PASS |
| Signer / identity / version | PASS |
| Permission and component audit (built APK) | PASS |
| R8 constructors / minified startup | PASS / PASS |
| Reproducibility (two clean builds) | PASS |
| Emulator: signed v1.1.0 → v1.2.0 upgrade, migration, data | PASS |
| Emulator: smoke, Hydration Coach, Focus Guard natural run, notifications, restore, network | PASS |
| iOS builds / simulator smokes | PASS / PASS |
| Security and privacy | PASS |
| **Physical OnePlus: backup, signed in-place update, real v5 → v6, data preservation** | **NOT RUN (authorization absent)** |
| Physical Hydration Coach / Focus Guard / notifications / update check | **NOT RUN** |
| CI on the final PR head | see [AE](#ae-pr-and-ci-evidence) |
| Independent review / merge | NOT RUN (owner) |
| Post-merge rebuild / publication / post-publication checks | NOT RUN (Gate D, not authorized) |

**Phase 11F release qualification INCOMPLETE. Do not merge for release
or publish until the listed blockers are resolved.** The blocker is the
physical signed upgrade on the owner's OnePlus, which needs the owner's
explicit authorization. Everything that could be qualified without
touching the production installation passed. **NOT TAGGED. NOT
PUBLISHED.**
