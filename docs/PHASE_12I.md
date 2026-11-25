# Phase 12I: NextRep v1.3.0 release qualification

## A. Objective and boundary

Qualify **NextRep v1.3.0** (the v1.3 roadmap, Phases 12E1–12H, PRs
#24–#31) for release: the exact release source, a candidate signed with
the permanent key, a real signed v1.2.0 → v1.3.0 in-place upgrade (schema
v6 → v7), data preservation, backup compatibility, Focus Guard, sounds,
accessibility and the release documents.

Release qualification only: **no feature, permission, dependency,
schema, backup-format or signing change**. App code changed only for the
version (`1.3.0+4`).

| Gate | What | Status |
|---|---|---|
| I (emulator and desktop) | Source, automated suite, signed candidate, reproducibility, signed upgrade rehearsal, backups, Focus Guard, functional regression | **done here** (§§ C–P) |
| I (physical) | Owner-authorized signed in-place upgrade on the owner's OnePlus; U-1, U-2, U-4, U-8 | **PENDING**: the owner was asked on 25 Nov 2026 and chose "not now". Request: [§ R](#r-gate-i-physical-device-authorization-request) |
| Review and merge | Independent review of the Phase 12I PR; owner merge | not started |
| P | Rebuild of merged `main`, byte identity, tag, draft, publication | **not authorized; not started** ([§ T](#t-publication-boundary-gate-p)) |

Results use **PASS**, **FIXED AND RETESTED**, **DEFERRED WITH REASON**,
**NOT RUN** and **BLOCKER**. Every PASS below was measured in this phase,
on this phase's source or candidate; nothing is carried over from an
earlier phase's evidence.

## B. Verified baseline

Checked before any change, on 25 November 2026:

| | |
|---|---|
| PR #31 (Phase 12H) | **merged** 25 Nov 2026 02:47 UTC; final head `67602902055001193d8b4547739665aaa2b05182`; squash commit `138fc6faffdf08e14ea97ea0cb222510a9108eb8` = `origin/main` |
| Post-merge CI | run [45535474488](https://github.com/arunachaleswaranms/NextRep/actions/runs/45535474488) on `138fc6f` (push to `main`): success; "Format, analyze and test" success, "Android builds and permission audit" success |
| Open PRs | none |
| Gate H | H-1 … H-6 approved, including C-1 and C-2 ([PHASE_12H.md § 14](PHASE_12H.md#14-copy-and-tone-decisions)) |
| Releases | v1.2.0 Latest (published 18 Oct 2026), v1.1.0, v1.0.0; **no `v1.3.0` tag or GitHub Release** (`git ls-remote --tags`, `gh release list`) |
| Source | `pubspec.yaml` `1.2.0+3`; package `com.nextrep.nextrep`; schema v7; backup write 4, read 1–4; 32 achievements; the seven approved permissions |
| Worktrees | all 15 clean, nothing unpushed. The signing checkout `~/labs/NextRep` was on `phase/11b-smart-hydration` at `15392ce`, clean and in sync, with `android/key.properties` (mode 600, git-ignored) |

Work happened in a new worktree `~/labs/NextRep-12I` on
`phase/12i-v1.3-release-qualification` from `138fc6f`. It has no
`key.properties`.

## C. Qualification matrix

| # | Requirement | Method | Evidence | Result | Remaining risk | Owner authorization |
|---|---|---|---|---|---|---|
| 1 | Version `1.3.0+4`; package, signer, schema, format, permissions unchanged | source diff, new release test, `aapt2` | § D, § F | PASS | — | — |
| 2 | Full automated suite green | format, analyze, `flutter test`, JVM | § E | PASS (2,460 / 87) | — | — |
| 3 | iOS builds and smoke | simulator build, release no-codesign, integration tests on iPhone 17 simulator | § E3 | PASS for the builds and the 1.3-relevant smokes; 4 historical smokes **DEFERRED** (pre-existing, identical on `138fc6f`) | stale historical integration tests | — |
| 4 | Candidate signed by the permanent key | release script in the trusted checkout; independent `apksigner` | § F | PASS | — | given (signing checkout detach, 25 Nov) |
| 5 | Same 7 permissions and merged components as v1.2.0 | `aapt2` diff against the published v1.2.0 APK | § F | PASS | — | — |
| 6 | Byte-reproducible | two clean signed builds, `cmp` | § G | PASS | holds for this fixed environment only | — |
| 7 | Real signed v1.2.0 → v1.3.0 upgrade, v6 → v7, every row kept | published v1.2.0 + synthetic data on a disposable AVD, `adb install -r`, `adb root` DB diff | § H | PASS (1,187 rows identical) | — | — |
| 8 | Backup compatibility (format 3 in, format 4 out, v1.2.0 refuses 4) | genuine v1.2.0 export; restore on the upgraded app; v1.2.0 on a second AVD | § I | PASS | — | — |
| 9 | Focus Guard after the upgrade (native gate 7, natural run) | Usage Access, chosen apps, natural JobScheduler run | § J | PASS | — | — |
| 10 | Functional regression of the minified signed candidate | real UI on two disposable AVDs, DB checks | § K | PASS (items not run listed) | see § K "not run" | — |
| 11 | D-1, D-2, C-1, C-2 on the signed candidate | real UI, pixel contrast, DB | § L | PASS | — | — |
| 12 | Sounds: silent, DND, ringer, off, preview, no focus | `dumpsys audio` playback events | § M | PASS (emulator, no listening) | U-1, U-4 need a person and a phone | **Gate I** |
| 13 | Manual update check with an installed candidate | per-UID netstats, live GitHub | § K | PASS | — | — |
| 14 | Physical OnePlus signed upgrade, TalkBack, headphones, OxygenOS, timings | — | § R | **NOT RUN: authorization pending** | U-1, U-2, U-4, U-8 open | **Gate I** |
| 15 | Release documents | review | § Q | PASS | — | — |
| 16 | Secrets and artifacts kept out of Git | diff and tracked-file audit | § S | PASS | — | — |
| 17 | No publication | — | § T | held | — | **Gate P** |

## D. Version bump

| | Before | After |
|---|---|---|
| `pubspec.yaml` | `version: 1.2.0+3` | `version: 1.3.0+4` |
| `lib/app/app_info.dart` | `appVersion = '1.2.0'` | `appVersion = '1.3.0'` |
| Android versionName / versionCode | 1.2.0 / 3 | **1.3.0 / 4** (`flutter.versionName` / `flutter.versionCode`; the built APK checked by `aapt2`, § F) |
| iOS `CFBundleShortVersionString` / `CFBundleVersion` | 1.2.0 / 3 | **1.3.0 / 4** (built `Runner.app` read with `PlistBuddy`) |

Not changed: package id, `namespace`, signing, `AndroidManifest.xml`,
`pubspec.lock`, schema v7, format 4, achievements, any feature.

Every reference to the old version was reviewed:

- **This build → 1.3.0.** `integration_test/phase11d_about_smoke_test.dart`
  and `phase11e_ios_smoke_test.dart` read the installed app on the
  simulator and now expect "Version 1.3.0", "Build 4";
  `phase11d_about_flow_test` "this build" (from `pubspecVersion()`)
  likewise; the About screen's doc comment example.
- **The published v1.2.0 → kept, retargeted.**
  `test/app/phase11f_release_test.dart` described "this build" as 1.2.0.
  Its checks that pinned **this source** to 1.2.0 (pubspec 1.2.0+3,
  `appVersion` 1.2.0, a fresh export recording 1.2.0) moved, with the same
  strictness and the new values, to the new
  `test/app/phase12i_release_test.dart`. What stays in the 11F file is the
  published v1.2.0 install (a fake installed 1.2.0 (3)): its update-check
  answers against GitHub, its About screen and its version comparisons,
  which v1.2.0 users still run, plus one check that this source is past
  v1.2.0. Net −2 tests there, +17 in the new file. Nothing was weakened:
  every removed assertion has a 1.3.0 counterpart.
- **History → kept.** Backup fixtures, migration fixtures, the fake
  installed v1.1.0 of the 11D / 11E suites, release notes and phase
  records.

### Release-identity tests (`test/app/phase12i_release_test.dart`, 17)

| Item | Test |
|---|---|
| Version | `pubspec.yaml` is `1.3.0+4`; `appVersion` is `1.3.0` and parses to 1.3.0 |
| Android | versionName / versionCode from `pubspec.yaml`; `applicationId` and `namespace` `com.nextrep.nextrep`; no `applicationIdSuffix` or `versionNameSuffix` |
| Invariants | schema 7; backup write 4, read {1, 2, 3, 4}; 32 achievements; the source manifest requests exactly `INTERNET`, `RECEIVE_BOOT_COMPLETED`, `PACKAGE_USAGE_STATS` and removes `FOREGROUND_SERVICE`, `ACCESS_NETWORK_STATE` (the merged seven are checked on the APK) |
| Ordering | v1.2.0 < v1.3.0 by version and tag; v1.3.1, v1.10.0 newer; v1.2.9 older |
| Installed | the v1.3.0 APK reports 1.3.0 (4) through `PlatformInstalledAppSource` |
| Before publication | latest v1.2.0 → `NewerBuildInstalled` (never available or up to date); a v1.2.0 draft or prerelease → invalid |
| After publication | latest v1.3.0 → `UpToDate` |
| Synthetic future | v1.3.1, v1.4.0, v1.10.0 with both assets → available, official page; v1.4.0 missing either asset, an asset still uploading, or v1.3.0's files → not ready; drafts, prereleases, `-rc1`, no `v`, string `"false"`, a foreign page → invalid |
| About | "Version 1.3.0" / "Build 4"; no request in 5 minutes; one request per tap; "This build is newer than the latest published release." / "Installed: v1.3.0 · Latest published: v1.2.0"; after publication "Latest published: v1.3.0"; v1.4.0 "available" |
| Backups | a fresh export records `appVersion` 1.3.0, format 4, product NextRep, validates; restored on a fresh install and re-exported, its `data` is identical |

CI: the "Release qualification tests" step now also runs
`phase12i_release_test.dart` and `phase11f_release_test.dart` (both were
already in "All tests"). Nothing else in CI changed.

## E. Automated qualification

On the candidate source `9ce26ee` in `~/labs/NextRep-12I`. Environment:
Flutter 3.47.5 (framework `6a19cca564`), Dart 3.13.4, OpenJDK 21.0.12.1
(Homebrew), Android build-tools 36.0.0, Xcode 27.0, macOS 27.2.

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | **PASS**: 421 files, 0 changed |
| `flutter analyze` | **PASS**: no issues |
| `flutter test` (all) | **PASS: 2,460 / 2,460**, 0 failed, 0 skipped (2,445 at the 12H head + 17 new − 2 moved; § D) |
| `./gradlew :app:testDebugUnitTest --rerun-tasks` | **PASS: 87 / 87** (FocusGuardCheck 30, FocusGuardStore 18, UsageEventsCalculator 23, CompletionSounds 16) |
| `dart run tool/sounds/generate_completion_sounds.dart --check` | **PASS**: 6 files, 125,064 bytes, reproduce |
| `flutter build apk --debug` | **PASS** |
| `flutter build apk --release` (no key: debug-signed compile and audit artifact, never installed or distributed) | **PASS** (68.1 MB) |
| The release script's own gates in the signing checkout, twice | format clean, analyze clean, **2,460 / 2,460** each time |

### E2. Focused suites (from the same full run, per CI step)

| CI step | Tests |
|---|---|
| Migrations v1 → v7 | 79 / 79 |
| Backup formats (write 4; read 1–4) | 132 / 132 |
| Lifecycle foundation | 72 / 72 |
| Weekly Review | 169 / 169 |
| Calendar | 96 / 96 |
| Phase 12D (ordering, saved setup, Confirm & Start) | 160 / 160 |
| Phase 12E2 (Freeze and Resume) | 146 / 146 |
| Phase 12F (Restart and Delete) | 220 / 220 |
| Phase 12G (completion sounds, incl. G-R1 stale requests dropped) | 127 / 127 |
| Phase 12H (integration, reconciliation, migration chain, genuine legacy backups, layouts, midnight, restart on a resume day) | 125 / 125 |
| Focus Guard | 104 / 104 |
| Manual update check, network boundary, routes | 192 / 192 |
| Release qualification (identity 1.3.0+4, 11F, lifecycle, accessibility, dates) | 71 / 71 |
| Hydration Coach (3 files) | 69 / 69 |
| Layout sweeps (7 files) | 448 / 448 |

### E3. iOS

| Check | Result |
|---|---|
| `flutter build ios --simulator --debug` | **PASS** |
| `flutter build ios --release --no-codesign` | **PASS**; `Runner.app` 1.3.0 / 4 |
| `integration_test/phase11d_about_smoke_test.dart` (iPhone 17 simulator) | **PASS**: "Version 1.3.0, Build 4, no update check offered" |
| `integration_test/phase11e_ios_smoke_test.dart` | **PASS** (Arc, habits, Hydration Coach UI, no Focus Guard, About 1.3.0 (4), backup screen, 0 HTTP clients) |
| `day_one_smoke_test`, `phase2_smoke_test`, `phase7_release_smoke_test` | **PASS** |
| `phase3_smoke_test`, `phase4_smoke_test`, `phase5_smoke_test`, `phase6_smoke_test` | **DEFERRED WITH REASON: pre-existing.** They fail on stale expectations from before v1.1 ("0/15" and "Achievements: 6 / 15" from when there were 15 achievements, a Phase 5 tap target at line 171, "Last night · 23:10"). Re-run on the untouched baseline `138fc6f` (version 1.2.0+3): **the same four fail at the same lines**. CI never runs `integration_test/`, and the 12I version change doesn't touch them. Recommend refreshing them in a later phase; not a release blocker |
| `phase12h_performance_test` (`flutter drive --profile`) | NOT RUN (informational timings; U-8 belongs on the phone) |

## F. Signed candidate (permanent key)

### F1. Signing environment

With the owner's explicit permission (25 November 2026), the trusted
signing checkout `~/labs/NextRep` was detached at the candidate commit
`9ce26ee70472694988f7fb0aeefbd7766e6128bc` (reachable through the shared
object store; nothing pushed for it):

- before: branch `phase/11b-smart-hydration` at `15392ce`, clean, in sync;
  `android/key.properties` mode 600, git-ignored
  (`android/.gitignore:12`), keys `keyAlias`, `keyPassword`, `storeFile`,
  `storePassword` (names only; **no value was read, printed or copied**);
- its staged v1.2.0 files in `build/release-candidate/` were first copied
  to a private folder outside every repository
  (`~/nextrep-release-candidates/`, mode 700) and verified (`shasum -c`
  OK), because `flutter clean` deletes `build/`;
- `JAVA_HOME` = OpenJDK 21 (the recorded release environment);
  `flutter clean` then `tool/release/prepare_android_release.sh`, twice;
- after: back on `phase/11b-smart-hydration` at `15392ce`, clean,
  `key.properties` untouched (mtime 8 Oct); the v1.2.0 staged files put
  back beside the new candidate. Generated, git-ignored build files there
  now reflect the 1.3.0 build and are regenerated by the next Flutter
  command.

The release script was read before use: it requires a clean tree and
`key.properties`, runs the gates, builds, and verifies signer, package,
version, the exact permission set, forbidden permissions and binds,
foreground services, WebView, the Focus Guard provider (present, not
exported) and the R8 constructors, then stages the APK and its checksum.
It never reads the password, creates keys, tags, pushes or uploads.

### F2. Independent verification of the staged APK

`apksigner verify --verbose --print-certs`, `aapt2 dump badging /
permissions / xmltree`, `apkanalyzer dex packages`, `unzip -v`, compared
with the **published** v1.2.0 APK:

| Check | Result |
|---|---|
| Signature | **verifies**; APK Signature Scheme v2 only (v1, v3, v3.1, v4 not used; minSdk 24) |
| Signers | exactly **1**: `CN=Arunachaleswaran M S, OU=NextRep` (not `CN=Android Debug`), RSA 4096 |
| Certificate SHA-256 | **`65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba`** = the permanent certificate (and v1.2.0's) |
| Identity | `package: name='com.nextrep.nextrep' versionCode='4' versionName='1.3.0'`; minSdk **24**, targetSdk **36**, compileSdk 36 (the existing configuration); label NextRep; native code arm64-v8a, armeabi-v7a, x86_64; not debuggable |
| Permissions | `aapt2 dump permissions` **identical to v1.2.0's**: `INTERNET`, `RECEIVE_BOOT_COMPLETED`, `PACKAGE_USAGE_STATS`, `WAKE_LOCK`, `VIBRATE`, `POST_NOTIFICATIONS`, `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (7) |
| Forbidden | none of the release script's forbidden permissions; no Accessibility, VPN or notification-listener service; no `SystemForegroundService` / `foregroundServiceType`; no `WebViewActivity`; no `usesCleartextTraffic` or `networkSecurityConfig` attribute; no `ACCESS_NETWORK_STATE` |
| Components | **19, identical to v1.2.0** (name, exported, permission, process, enabled): `MainActivity` exported (launcher); `SystemJobService` exported, `BIND_JOB_SERVICE`; `DiagnosticsReceiver` and `ProfileInstallReceiver` exported, `DUMP`; **`FocusGuardCheckProvider` not exported, process `:focus_guard`**; every other provider, service and receiver not exported |
| R8 | kept: `androidx.work.impl.WorkDatabase_Impl <init>()`, `FocusGuardWorker <init>(Context, WorkerParameters)`, `FocusGuardCheckProvider <init>()` |
| Sounds | six WAVs under `assets/flutter_assets/assets/sounds/`, all **Stored** (uncompressed): 11,244, 28,844, 14,444, 28,844, 12,844, 28,844 bytes |

**PASS.**

## G. Reproducibility

| | |
|---|---|
| Source | `9ce26ee70472694988f7fb0aeefbd7766e6128bc` |
| Toolchain | Flutter 3.47.5 / Dart 3.13.4, OpenJDK 21.0.12.1, Android build-tools 36.0.0 (`apksigner`, `aapt2`), macOS 27.2 |
| Configuration | `flutter build apk --release` through the release script; R8 on; no `--obfuscate`; signed by the permanent key |
| Signer | `65b70cd0…f0ba` |
| Build 1 | `flutter clean` + script (gates 2,460 / 2,460): **68,142,073 bytes**, SHA-256 **`a706759703f8894c2ef33772bb7d48a04e23fb0685b0e0639ffce8997754ec7f`**; copied to `~/nextrep-release-candidates/v1.3.0-build1/` before the next clean |
| Build 2 | `flutter clean` + script (gates 2,460 / 2,460): 68,142,073 bytes, SHA-256 `a706759703f8894c2ef33772bb7d48a04e23fb0685b0e0639ffce8997754ec7f` |
| `cmp` | **byte-identical**; the two `.sha256` files are identical too |

**PASS** for this fixed local environment (same commit, key and
toolchain). It isn't a claim of universal reproducibility. The candidate
stays private and git-ignored (outside the repository and in the signing
checkout's `build/release-candidate/`); it was not uploaded or shared.

## H. Signed v1.2.0 → v1.3.0 upgrade rehearsal (disposable emulator)

### H1. Device and safety

| | |
|---|---|
| AVD | **`NextRep12I_API36`**, created for this phase (`system-images;android-36;google_apis;arm64-v8a` r7, `pixel_7`), `emulator-5560`, Android 16 (API 36), Asia/Kolkata; emulator 37.1.11. Deleted at the end of the phase |
| Second AVD | `NextRep12I_v120_API36` (`emulator-5562`), for v1.2.0's refusal of format 4 and the fresh install (§§ I, K). Deleted at the end |
| Other devices | none attached. The other project's AVD was not started. The owner's phone was not connected or touched |
| Data | synthetic only (invented habits and reflections) |
| Commands | every `adb` call named the serial explicitly. `adb root` only on these AVDs, to read the database (release builds aren't debuggable) |

### H2. Before the upgrade (official v1.2.0, its own app and services)

1. **Published v1.2.0:** `gh release download v1.2.0`; `shasum -a 256 -c`
   OK; 66,360,265 bytes, `e3847628…de3e2`, byte-identical to the staged
   copy in the signing checkout; `apksigner` one signer `65b70cd0…f0ba`;
   `aapt2` `com.nextrep.nextrep` 1.2.0 (3).
2. Installed on `emulator-5560`: `firstInstallTime` **2026-11-25
   09:18:29**, `signatures:[487b1b9c]`, no past signatures.
3. **Seed:** `tool/screenshots/generate_screenshot_backup.dart` run from a
   detached worktree at **tag `v1.2.0`** (`8ab0c43`) with
   `SCREENSHOT_DATE=2026-11-25`. It builds the data through v1.2.0's own
   services and exports a format-3 file: a completed Seasonal Arc 2025
   (late join on 15 Oct, a custom habit "Stretch", Sleep Before on,
   Perfect, partial, missed and Minimum Days, achievements, reflections)
   and an active Rolling Arc on Day 20. Restored through v1.2.0's
   onboarding **Restore from a backup**.
4. In v1.2.0's UI: Water goal 8 → 10 glasses, minimum 3 → 4, **from
   tomorrow** (revision); English Practice switched **on from tomorrow**
   (revision; Meditation stays off); No Junk Food completed (+15 XP, 1,935
   → 1,950); **daily reminder on** at 08:00 (notification permission
   allowed), evening reflection off; **Hydration Coach on, Supportive**,
   08:00–20:00; **Focus Guard**: Usage Access granted on the system page,
   Clock and Calendar chosen, a **7-minute** budget, switched on (one
   WorkManager job, enqueued 09:25:33).
5. **Pre-upgrade backup** in v1.2.0 (Data & Backup → Export → Downloads):
   format **3**, appVersion 1.2.0, 194,875 bytes, SHA-256 `ec2df17c…67b7`
   (identical on the device and the Mac; the Mac copy kept read-only,
   outside the repository). Checked with v1.3.0's own `BackupCodec` and
   `BackupValidator` (counts only): decode and validate OK.

   | Arc | habits | revisions | progress | day modes | XP rows (XP) | unlocks | reflections |
   |---|---|---|---|---|---|---|---|
   | Seasonal 2025, completed | 8 | 0 | 398 | 7 | 448 (7,575) | 26 | 36 |
   | Rolling from 6 Nov 2026, active | 8 | 2 | 104 | 2 | 116 (1,950) | 15 | 11 |

   Reminder times 08:00 / 21:00, window 08:00–20:00, Supportive; Focus
   Guard budget 7, 2 apps.
6. **v6 database** (`adb root`, `pull`): `user_version` **6**,
   `journal_mode` delete, `integrity_check` ok, `foreign_key_check` empty;
   11 tables, **1,187 rows**: `winter_arc_sessions` 2, `habits` 16,
   `habit_revisions` 2, `daily_habit_progress_entries` 502, `day_modes` 9,
   `xp_transactions` 564, `achievement_unlocks` 41, `daily_reflections` 47,
   `reminder_preferences` 1, `focus_guard_preferences` 1,
   `focus_guard_selected_apps` 2. One Focus Guard job; notification
   permission granted; `GET_USAGE_STATS: allow`.

### H3. The upgrade

Candidate re-verified (`shasum -c` OK), then
`adb -s emulator-5560 install -r NextRep-v1.3.0-android.apk` (no `-d`,
no uninstall, no `pm clear`) → **Success** (09:28:14).

| After the install | |
|---|---|
| Package / version | `com.nextrep.nextrep` **1.3.0 (4)** |
| `firstInstallTime` | 2026-11-25 09:18:29 (**unchanged**) |
| `lastUpdateTime` | 2026-11-25 09:28:14 |
| Signer | same (`signatures:[487b1b9c]`, no past signatures) |
| Installed `base.apk` | SHA-256 `a7067597…54ec7f` = the candidate |
| Before first launch | database still `user_version` 6 (the native worker leaves it alone; addendum C6) |
| Permissions | notification permission and Usage Access kept |

First launch: `WARM` 842 ms (Android had started the process for
`MY_PACKAGE_REPLACED`); no crash, no `E/flutter`.

### H4. Real v6 → v7 migration, row by row

The v7 file after the first launch, compared with the v6 snapshot by a
script that selects every v6 column of every v6 table, ordered by all
columns:

| | |
|---|---|
| `user_version` | 6 → **7** |
| Integrity / foreign keys | `ok` / none |
| v6 tables | **all 11 identical, 1,187 rows, every value** |
| DDL changes | only `winter_arc_sessions` gains `"closed_on" TEXT NULL` |
| New objects | `arc_freezes` (empty), `feedback_preferences` (empty), `one_open_freeze` index; their SQL matches [PHASE_12E1.md](PHASE_12E1.md#schema-v7-one-additive-step) |
| `closed_on` | NULL on both Arcs |
| `sqlite_sequence` | unchanged (`winter_arc_sessions` 2, `xp_transactions` 564) |
| Removed objects | none |

No legitimate difference was needed to explain: nothing was rewritten,
re-dated, duplicated or awarded by the upgrade.

### H5. The app after the upgrade

- Today identical to before: Day 20 of 92, 1,950 XP, Level 8 (200 / 250),
  Perfect streak 1 · best 4 · 14 total, 4 of 6 done, 15 of 32
  achievements; plus the new Sound & Feedback button.
- **Sound & Feedback:** on, Ice Crystal (the approved defaults with no
  row); opening the screen wrote no row.
- **Reminders (upgrade ≠ restore):** still on. 43 pending alarms, counted
  by `origWhen`: the daily reminder at 08:00 for 26 Nov – 8 Dec (13) and
  Hydration Coach Supportive, 5 a day within 08:00–20:00, for 26 Nov – 1
  Dec (30); none on 25 Nov, where Water was already met. (A plain line
  count of the receiver's tag also counts alarm-statistics lines, so it
  isn't comparable before and after.) One Focus Guard job, the one v1.2.0
  had enqueued.
- About: **Version 1.3.0 · Build 4**.

**Signed update continuity and data preservation: PASS.**

## I. Backup compatibility after the signed upgrade

Kept separate from § H: the upgrade preserved the data without any
restore.

| # | Check | Result |
|---|---|---|
| 1 | v1.3.0 inspects the genuine v1.2.0 format-3 file | **PASS**: the app's preview (2 Arcs, 1 completed, active 6 Nov 2026 – 5 Feb 2027, 47 reflections, 41 achievements); the codec on the Mac (§ H2) |
| 2 | Restores it on the upgraded device (by then a different state: a restarted, deleted and re-paused history, § K) | **PASS**: two confirmations ("Replace current data? This device has 2 Arcs and 36 reflections…", **Replace Data**) |
| 3 | Restored Arc data equals the source | **PASS**: normalised comparison with the v6 snapshot (Arcs keyed by kind and start date, since a restore assigns new ids; XP row ids ignored): `winter_arc_sessions`, `habits`, `habit_revisions`, progress (502), day modes (9), XP (564), unlocks (41), reflections (47) **identical**; `arc_freezes` empty, `closed_on` null |
| 4 | Reminders, Hydration Coach and Focus Guard off | **PASS**: daily reminder and Hydration Coach off with 08:00 / 21:00, 08:00–20:00 and Supportive kept; Focus Guard off with its 7-minute budget and both apps (same order) kept; 0 jobs, 0 alarms, 0 notifications |
| 5 | No XP, achievement or sound | **PASS**: XP and unlock rows equal the source although the device date was two days later; **0** playback starts during the restore (`dumpsys audio`) |
| — | Sound setting from an older format | **PASS**: format 3 has none, so this device's own setting (off, Summit Spark) was kept |
| 6 | A new v1.3.0 export is format 4 | **PASS**: right after the upgrade, format **4**, appVersion 1.3.0, 194,949 bytes, decode and validate OK. Against the pre-upgrade file, every Arc is identical apart from format 4's `freezes: []`; `reminders` and `focusGuard` identical; `feedback` null (no row yet) |
| 7 | v1.2.0 refuses a genuine format-4 file and changes nothing | **PASS** on `emulator-5562`: the **published** v1.2.0, the v1.2.0 synthetic seed restored, then the post-upgrade format-4 file picked in Restore Backup → "**Can't use this file.** That backup was made by a newer version of NextRep. Update the app to restore it. Nothing was changed." The v1.2.0 database file is **byte-identical** before and after (v6, 1,187 → same rows) |
| — | Formats 1 and 2 | automated: the genuine v1.0 / v1.1 files restore in `phase12h_backup_test`, `backup_v4_test` and the 11F file (§ E2, backup step 132 / 132). Not re-run on the device |

## J. Focus Guard after the upgrade

| Check | Result |
|---|---|
| Native store accepts schema 7 (real) | **PASS**: the post-upgrade natural run (below) opened the migrated v7 file in `:focus_guard` and claimed `last_nudged_on` |
| Old / unsupported schema fail closed | **PASS (JVM, not native on a device)**: `FocusGuardStoreTest` `theGateAcceptsExactlySchema7`, `aSchema6DatabaseIsLeftAlone`, `aNewerSchemaIsLeftAlone`, `schema7ReadsAndClaimsAsBefore` (87 / 87). The device-level v6 window (after install, before first launch) was not hit by a run in this rehearsal |
| Usage Access respected | **PASS**: `GET_USAGE_STATS: allow` kept across the update; the run measured the chosen apps |
| Apps and budget persist | **PASS**: rows identical (§ H4); the screen shows Clock, Calendar and 7 min |
| **Natural background run after the upgrade** | **PASS**: Clock in the foreground from 09:29:59. The job v1.2.0 had enqueued became eligible at 09:40:32; JobScheduler **started it on its own at 09:48:20** (`START #u0a213/0`, no `cmd jobscheduler run`), about 30 s after NextRep was brought to the foreground; `:focus_guard` process started; `WM-WorkerWrapper: Worker result SUCCESS … FocusGuardWorker`; `last_nudged_on` = 2026-11-25 in the v7 database |
| Notification | **PASS**: exactly one, channel and tag `focus_guard`, id 1: "You've reached today's 7-minute Focus Guard budget. Time to come back to your Arc?" |
| No launch, overlay or network | **PASS**: no activity started by the run; app UID bytes unchanged by it (§ K, update check) |
| Reminders and Hydration still work | **PASS** (§ H5, § K) |
| Boot, force-stop, relaunch | **PASS** (§ K): reboot without opening the app → 1 job and 43 alarms back (`BOOT_COMPLETED`); force-stop → 0 / 0, reopen → 1 / 46; database unchanged throughout |

Distinction kept: the schema gate's refusal paths are JVM results; the
schema-7 acceptance is a real native background run.

## K. Signed candidate functional regression

Minified, signed candidate on `emulator-5560` (upgraded data) and
`emulator-5562` (fresh install). Real taps through uiautomator; persisted
state read with `sqlite3`.

| Area | Result |
|---|---|
| Initial launch (fresh install) | **PASS**: 5562, v1.2.0 uninstalled there first (that disposable AVD only; its v1.2.0 role was done), candidate installed, `COLD` 1,092 ms, onboarding |
| Cold launch | **PASS**: `COLD` 696 ms and 721 ms after a kill / force-stop; data unchanged |
| About | **PASS**: Version 1.3.0 · Build 4 |
| Setup, ordering, saved setup, Confirm & Start | **PASS**: Move up (Learning 3 → 2) and a drag by the handle (Water → 1) each saved at once (`habits.sort_order`); Save for Later → "Your Arc Setup Is Saved · Rolling 92-Day · 7 habits · 4 on"; a cold relaunch reopens the hub; Review Setup lists the order, the minimums, the 3 habits off and reminders; Confirm & Start shows "Day 1: Today, Wednesday 25 November 2026" / "Day 92: Wednesday 24 February 2027"; after confirming, Day 1 and Today in the chosen order |
| Today habit completion | **PASS**: Stretch 0 → 5 → 10 min (+15 XP once), bedtime 23:30 (+15) |
| Perfect Day | **PASS**: "PERFECT DAY", 6 of 6, +30 bonus, 1,950 → 2,010 XP, Level 9 |
| Minimum Day | **PASS**: on the restarted Arc; minimum goals (Water 4, from the carried revision); `day_modes` row |
| Weekly Arc Review | **PASS**: Week 3 (Days 15–21): 25 of 30, 83 %; consistency 80 %; 465 XP; 3 Perfect, 1 Minimum; today kept apart |
| Arc Consistency Calendar | **PASS**: 13 week blocks; Week 3 "4 of 5 days full, this week. Opens the week review" |
| Journey, Journal, Insights | **PASS**: Journey summary; Journal today and past; Insights 9,585 XP = 7,575 + 2,010. **Read-only**: database content hash unchanged after visiting all of them |
| Freeze scheduling | **PASS**: Today ⋮ Pause Arc → sheet → `arc_freezes (2, 2026-11-26, open)`; banner; future reminders removed (0 alarms); **Cancel pause** → row deleted, 43 alarms back; paused again |
| Frozen state | **PASS**: emulator date set to 26 Nov → "Arc paused · Paused since today, Thursday 26 November 2026 · You stopped after Day 20 of 92" with Resume Arc and Restart |
| Resume | **PASS**: 27 Nov → "Today, Friday 27 November 2026, becomes Day 21 of 92. Your new last day is Saturday 6 February 2027. You paused for 1 day." → Day 21; pause `[26 Nov, 27 Nov)`; `end_date` 5 Feb → 6 Feb 2027; 47 alarms; the revisions dated the paused 26 Nov took effect after the pause (7 on, Water 10) |
| Restart | **PASS**: § L (D-2, C-2): old Arc `ended`, `closed_on` 27 Nov, pause kept; new Arc 27 Nov – 26 Feb 2027, 8 habits, 0 XP |
| Ended Arc History | **PASS**: "Rolling Winter Arc, 6 Nov – 27 Nov 2026, ended early · day 21 of 92. Paused 1 day. Level 9, 2010 XP…"; summary "WINTER ARC ENDED EARLY · Ended early · Day 21 of 92 · Paused 1 day" |
| Optional typed DELETE | **PASS**: offered after the restart (Keep it chosen), then from the ended Arc's summary (Arc options → Delete Arc) → typed DELETE → only that Arc and its rows removed (pause, habits, XP, reflections); the completed Arc and the new Arc untouched; integrity ok |
| Sound & Feedback | **PASS**: preview Summit Spark (1 playback); selection and switch stored (`feedback_preferences`); § M |
| Reminders | **PASS** (scheduling): on, 08:00, alarms planned; restored off by a restore; on again → 43. Delivery of a reminder: NOT RUN in 12I |
| Hydration Coach | **PASS** (scheduling): on, Supportive, 5 a day within the window, none once Water was met, none on paused dates |
| Focus Guard | **PASS**: § J |
| Data & Backup | **PASS**: § I |
| Manual update check | **PASS**: app UID 10213 (`dumpsys netstats --poll`, UID stats): 0 / 0 bytes after the upgrade, migration, Today and 25 s on About; **one tap → 10,418 rx / 1,295 tx**, unchanged 30 s later and through every later step on that boot; answer from the live GitHub API: "**This build is newer than the latest published release.** Installed: v1.3.0 · Latest published: v1.2.0". No download, no installer. The fresh install on 5562: 0 / 0 |
| Background / foreground | **PASS**: HOME and return, state kept |
| Process death and relaunch | **PASS**: `am kill` and `force-stop` → cold relaunch, same Today, database content hash identical, no `FATAL` / `E/flutter` |
| Reboot | **PASS**: § J |
| Large text and reduced motion | **PASS** (one screen): 2× font scale and all animator scales 0 on the fresh install → Today lays out without clipping, header buttons on their own row (screenshot checked); full sweeps are automated (§ E2) |

**Not run in 12I** (covered by automated suites or earlier phases, and
not a release blocker): real delivery and tap routing of a reminder or
Hydration nudge; Seasonal Arc start and late join on a device; share
cards; achievement celebrations; notification-permission denial;
TalkBack on the emulator (12H did explore-by-touch; a device pass is
U-2).

Note: the manual clock moves (26 and 27 Nov) made UsageStats carry the
previous day's Clock time into "today" on Focus Guard's card ("18 of 7
minutes"): an emulator clock-jump artifact, not a product defect.
Automatic time was restored afterwards.

## L. Phase 12H fixes on the signed candidate

| Fix | Check | Result |
|---|---|---|
| **D-1** readable destructive buttons | screenshot pixels inside the red button: **Replace Data** (restore, 5560) and **Cancel Setup** (dialog, 5562) → text (7, 11, 24) on (255, 92, 138) = **6.68 : 1**, dark text | **PASS** |
| **D-2** Restart on the resume day, nothing logged | resumed on 27 Nov, nothing logged; Habits → Restart with this setup → offered, "Your current Arc ends at Day 21 of 92." → RESTART → `status ended`, **`closed_on` 2026-11-27** (the resume date), pause row `[26 Nov, 27 Nov)` **kept**; history "Paused 1 day" | **PASS** |
| **C-1** hub button | the saved-setup hub shows **"Cancel Setup"** | **PASS** |
| **C-2** Restart's habit count | "A new Rolling 92-Day Arc starts today on Day 1 with your **8 habits (7 on)**, goals and order." (8 habits; 7 on at their latest configuration, English Practice having been switched on); the new Arc has 8 habits | **PASS** |

## M. Completion sounds and accessibility (emulator)

Evidence is Android's own playback record (`dumpsys audio`: NextRep's
`SoundPool` player, `USAGE_ASSISTANCE_SONIFICATION`, and
`event:started`). Nobody listened; that is a Gate I item.

| Check | Playback starts | Result |
|---|---|---|
| Habit completion (Stretch reaching 10 min), normal ringer | 1 (none for the 5-minute step or taps past the target) | PASS |
| The completion that makes Perfect Day | 1 (none for the level-up) | PASS |
| Preview (Summit Spark) | 1 | PASS |
| Sounds switched off, then a completion | 0 | PASS |
| Ringer **SILENT**, completion | 0 | PASS |
| **Do Not Disturb** (priority), the Perfect Day completion | 0 | PASS |
| Normal ringer again, re-completion | 1 | PASS |
| Restore | 0 | PASS |
| Audio focus requested by NextRep | none | PASS |
| XP after undo / redo | 567 rows, 567 distinct keys, 9,585 XP: no duplicate | PASS |

| Device item (owner's phone) | Status |
|---|---|
| Vibrate ringer, music playing (no ducking), headphones / Bluetooth, OxygenOS, the 1 s "never late" rule (U-4) | **NOT RUN: Gate I** |
| TalkBack speech continuity with a sound (U-1); swipe order and double-tap (U-2); confirmations, ordering alternatives, Perfect Day announcement by a listener | **NOT RUN: Gate I** |
| Real-device timings (U-8) | **NOT RUN: Gate I** |

## N. Permission, dependency and network audit

- **Permissions:** exactly the seven of v1.2.0 (§ F2), from an unchanged
  `AndroidManifest.xml` (byte-identical to `main`).
- **Dependencies:** `pubspec.yaml` changes only in its `version:` line;
  `pubspec.lock` byte-identical to `main`; nothing under `android/`,
  `ios/` or `assets/` changed.
- **Network:** no new network code; the only request is the user-tapped
  update check (§ K); the network-boundary and completion-sound boundary
  suites pass.
- **No** analytics, telemetry, automatic download or installer.

## O. Source changes in this phase

| Commit | Content |
|---|---|
| `984d086` | chore: bump NextRep to v1.3.0 (`pubspec.yaml`, `app_info.dart`, an About doc comment) |
| `9ce26ee` | test: qualify v1.3.0 release version and compatibility (new `phase12i_release_test.dart`; 11F test retargeted at the published v1.2.0; two iOS smokes and the 11D flow test expect 1.3.0 (4); the CI release step runs both release-identity files). **Signed candidate source** |
| later | documentation only (Markdown isn't packaged) |

## P. Environment and artifacts kept outside Git

- Candidates: `~/nextrep-release-candidates/v1.3.0-build1/`, `…-build2/`
  (mode 700 folder, outside every repository) and the signing checkout's
  git-ignored `build/release-candidate/`. The published v1.2.0 APK and the
  staged v1.2.0 copy sit beside them for comparison.
- Synthetic backups and database snapshots: the session's scratch folder,
  outside the repository; none committed.
- The temporary `v1.2.0`-tag worktree used for the seed and the baseline
  iOS check is removed at the end; the two AVDs are deleted.

## Q. Release documents

- New: [releases/v1.3.0.md](releases/v1.3.0.md) (status: release
  candidate, not published), this file.
- Updated: [README.md](../README.md) (status, the v1.3.0 features as
  coming, updating and backup formats), [CHANGELOG.md](../CHANGELOG.md)
  ("1.3.0 — release candidate (not yet published)", with privacy and
  compatibility), [PRIVACY.md](../PRIVACY.md) (1.3.0 wording, the same
  permissions, deletion), [DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md)
  (v1.3.0 over v1.2.0, schema upgrade, no downgrade, format 4 refused by
  v1.2.0), [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) (a fresh v1.3.0
  record), [PROJECT_STATE.md](../PROJECT_STATE.md).
- Nothing claims that v1.3.0 is published.

## R. Gate I: physical-device authorization request

**Status: PENDING.** The request below was put to the owner on 25
November 2026, after the emulator qualification and with PR #32 open. The
owner's decision: **"Not now: keep Gate I pending."** Nothing was
installed on, removed from or changed on any physical device; the phone
was not connected (`adb devices` and `adb mdns services` empty). The
request stands for a later decision; it authorizes nothing by itself.

| | |
|---|---|
| Candidate | `NextRep-v1.3.0-android.apk`, **68,142,073 bytes**, SHA-256 **`a706759703f8894c2ef33772bb7d48a04e23fb0685b0e0639ffce8997754ec7f`**, source `9ce26ee` |
| Signer | one signer, certificate SHA-256 `65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba` (the installed v1.2.0's) |
| Target device | the owner's OnePlus **CPH2707** (Android 16, OxygenOS), to be confirmed on connection by `ro.product.manufacturer`, `ro.product.model`, `ro.serialno` and `ro.kernel.qemu` empty; serial and addresses not recorded |
| Expected installed | `com.nextrep.nextrep` **1.2.0 (3)**, its `base.apk` byte-identical to the published v1.2.0 asset (`e3847628…de3e2`), signer `65b70cd0…f0ba`, `firstInstallTime` recorded first |
| Expected migration | schema v6 → v7 on first launch: adds `arc_freezes`, `feedback_preferences` and `closed_on`; changes no existing row. Sounds start on (Ice Crystal); reminders, Hydration Coach and Focus Guard stay as set |
| Before anything else | an **Export Backup** in v1.2.0 (format 3) to `Download/`, checked with the app's codec (counts only), copied to the Mac's private backup folder read-only and re-hashed after every step |
| Preservation checks | private UI baseline of Today, Journey, Journal, Insights, History, Achievements, Reminders, Focus Guard; after the update: the same screens, a post-update format-4 export normalised against the pre-update file (Arcs identical, only format-4 additions), `firstInstallTime` unchanged, same signer, installed APK = candidate |
| Actions that modify the phone | (1) the backup export (a new file in `Download/`); (2) `adb -s <verified serial> install -r` of the candidate; (3) launching v1.3.0 (runs the migration); (4) temporary test actions if wanted: Sound & Feedback changes and previews, ringer / DND / vibrate changes, TalkBack on and off, font size, a test habit completion (adds XP for that day), screen timeout raised then restored. Each restored afterwards where possible |
| Never | uninstall, `pm clear`, restore, downgrade, permission revocation by shell, deleting an Arc, Restart or Pause on the owner's real Arc (unless the owner asks for it) |
| Rollback limits | **no downgrade**: Android refuses v1.2.0 over v1.3.0, and v1.2.0 can't read a v1.3.0 backup. The way back to v1.2.0 is uninstall (deleting the data) + install v1.2.0 + restore the **pre-update format-3 backup**: hence the off-device copy first. Test XP added on a real day stays in the history |
| Tests planned | the signed in-place update and preservation; smoke of every v1.3 feature (read-only where possible: Weekly Review, Calendar; ordering and saved setup only if the owner has no running Arc or wants it); sounds on normal ringer, silent, vibrate, DND, with music playing, with headphones or Bluetooth if available, habit and Perfect Day sounds, previews, sounds off, rapid repeats, the 1 s cutoff if reproducible (U-4); TalkBack swipe order, double-tap, confirmations, ordering alternatives, the Perfect Day announcement and **speech continuity during a sound, judged by the owner listening** (U-1, U-2); large text and reduced motion; optional profile timings (U-8); the manual update check (expected "newer than the latest published v1.2.0") |
| Stop conditions | device identity, installed version, installed APK hash or signer not as expected; the backup fails to export or verify; `install -r` fails or reports a signing conflict (**stop, never uninstall**); onboarding, a crash or missing data after the update; any difference in the preserved data; anything the owner asks to stop |
| Results | each item PASS, FAIL, UNRESOLVED or NOT RUN; a person must confirm audibility and speech continuity; no energy measurement substitutes for listening; no private data in logs, docs or the PR |

If the owner doesn't authorize it, Gate I stays open with the physical
qualification explicitly pending, and the release is not fully qualified.

## S. Secret, artifact and data audit

Before the PR, the branch diff and every tracked file were checked for
keystores (`*.jks`, `*.keystore`), `key.properties`, passwords, tokens,
APKs, `.sha256` artifacts, backups (`*.nextrep`), databases
(`*.sqlite`), device dumps, logcat captures and personal data.

**PASS:** no such file is tracked (the only `.nextrep` files are the three
existing synthetic test fixtures); the added lines mention `keyAlias`,
`keyPassword`, `storeFile` and `storePassword` only as names, with no
value; no email address, device serial, network address, token or
private path to a backup appears. The documents carry only public values
(the certificate fingerprint, the candidate's hash and size) and
synthetic examples. Candidates, backups and database snapshots stay
outside the repository (§ P).

## T. Publication boundary (Gate P)

Not done, and not authorized: no tag `v1.3.0`, no GitHub Release or
draft, no asset upload, no public link to the candidate, no change to
`releases/latest`, no installation on a physical device.

The planned order after this PR:

1. Independent review of the Phase 12I PR.
2. Owner approves Gate I (the physical qualification above, or an
   explicit decision about it).
3. Owner merges.
4. Post-merge CI green.
5. Rebuild the merged `main` with the permanent key (`flutter clean` +
   release script) and compare with `a7067597…54ec7f`. Documentation-only
   commits after `9ce26ee` don't change the APK; a mismatch stops
   publication for investigation.
6. **Separate Gate P authorization.**
7. Only then: annotated tag, draft release with the APK and `.sha256`,
   downloaded and compared, published; unauthenticated public
   verification and `releases/latest`.

## U. Known limitations

- **Physical qualification pending (Gate I)**: U-1, U-2, U-4, U-8 open.
- Four historical iOS integration smokes (phases 3–6) are stale and fail
  the same way on the baseline (§ E3).
- From Phase 12H, unchanged: U-3 reorder drag animation under reduced
  motion (H-3); U-5 iOS sound and VoiceOver (no iOS release); U-6 G-R1
  residual (≤ ~300 ms, non-router transition); U-7 a clock set back on
  the scheduling day can't be detected offline.
- Focus Guard waits for the first launch after an update (the v6 file is
  left alone until migrated).
- Reproducibility is shown for one fixed environment.

No **BLOCKER** is open.
