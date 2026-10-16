# Phase 11E: Full integration and regression qualification

## A. Objective

Qualify the integrated v1.2 line (Phases 11A–11D on `main`) as one app:
the established Winter Arc product, Smart Hydration, Focus Guard and the
manual update check working **together**, across notifications, the
database, backups, dates and the Android and iOS lifecycles. Fix only
demonstrated defects, add permanent regression tests for them, and hand a
precise checklist to Phase 11F.

No feature was added. Version **1.1.0+2**, schema **v6**, backup write
**3** / read **1, 2, 3**, package `com.nextrep.nextrep` and the release
signer are unchanged. Nothing was tagged, published or distributed. Phase
11F was not started.

## B. Verified baseline

| | |
|---|---|
| `origin/main` | `1eed4f8fef49fb3ea4bfefffd701129d822d68be`, "Phase 11D: add About screen and manual update checking (#18)", fetched and verified before any change |
| Merged | PR #15 (11A), #16 (11B), #17 (11C), #18 (11D) |
| Main CI | run 38782774357 on `1eed4f8`: success |
| Published | GitHub Release `v1.1.0` (Latest), `v1.0.0`; nothing for v1.2 |
| Source version | `pubspec.yaml` `1.1.0+2`, `appVersion` `1.1.0` |
| Database / backup | schema v6; backup write 3, read 1 + 2 + 3 |
| `flutter test` at baseline | **1144 / 1144** (re-run here on `1eed4f8`) |
| Native JVM at baseline | **67 / 67** (re-run here) |
| Format / analyze at baseline | 297 files, 0 changed / no issues |
| Branch | `phase/11e-integration-regression` from `1eed4f8`, in a separate worktree (`~/labs/NextRep-phase11e`) without `android/key.properties` |

Tooling: Flutter 3.47.5 / Dart 3.13.4, Android build-tools 36.0.0, Xcode
27.0, macOS host in Asia/Kolkata.

## C. Regression matrix

Results: **PASS**, **FAIL**, **NOT RUN**, **BLOCKED**, **NOT APPLICABLE**.
"Auto" evidence is a test in this repository; "Device" is the API 36
emulator run in [P](#p-android-emulator-evidence); "Sim" is the iOS
simulator in [Q](#q-ios-build-and-simulator-evidence). Every row was
executed in this phase unless it says NOT RUN.

### C1. Core Winter Arc, habits, XP and Minimum Day

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C1.1 | Fresh install | no data | launch | onboarding | Device E2 (minified); Sim; Auto `phase11e_combined_flow_test` | PASS |
| C1.2 | Rolling Arc setup | onboarding | Let's Begin → Rolling → Start | Day 1 of 92 | Device E3 (16 Oct 2026 – 15 Jan 2027); Sim; Auto combined flow | PASS |
| C1.3 | Seasonal window, late join | season in progress | join | days before joining don't count | Auto `seasonal_arc_test`, `participation_test` (core set) | PASS |
| C1.4 | 92 days exactly | any Arc | — | end = start + 91 | Device E3 (16 Oct → 15 Jan); Auto `arc_lifecycle_test` | PASS |
| C1.5 | Setup survives navigation / restart | setup | About from setup, relaunch | setup intact | Auto `phase11d_about_flow_test`, `day_one_flow_test` | PASS |
| C1.6 | Rollover while open | Arc, app on Today | cross 23:59:5x → 00:00 | new day, no tap | Device E16 (Day 1 → Day 2); Auto `phase11e_lifecycle_test` (midnight) | PASS |
| C1.7 | Rollover while backgrounded | Arc | pause, day passes, resume | new day, one re-plan | Auto `phase11e_lifecycle_test` (background day change); Device E17 | PASS |
| C1.8 | Rollover after process death | Arc | kill, relaunch next day | new day, same plan, no duplicates | Auto `phase11e_lifecycle_test` (process death) | PASS |
| C1.9 | Day 92 → 93 | Arc on Day 92, everything on | midnight while open | Arc completes; summary; reminders stop | Auto `phase11e_lifecycle_test` (Day 92 → 93) | PASS |
| C1.10 | Completed Arc read-only, history intact | completed + new Arc | open history | read-only, unchanged | Auto `phase5_flow_test`, `multi_arc_test`, `phase11e_restore_test` | PASS |
| C1.11 | New Arc doesn't overwrite history; no leak | completed Arc | start new (reuse / fresh) | old rows unchanged | Auto `multi_arc_test`, `winter_arc_service_test`, `phase11e_restore_test` | PASS |
| C1.12 | Habits: binary, numeric, clock-time, custom, rename, target revisions, enable/disable, max 12, duplicates | — | — | locked rules | Auto `habit_edit_timing_test`, `setup_habits_test`, `time_before_test`, `phase6_flow_test`, `phase10c_flow_test` | PASS |
| C1.13 | Completion, undo, XP award and rollback | Today | complete / undo | +XP / −XP, once per tap | Device E4 (15 XP); Auto `day_one_flow_test`, `phase2_tracking_test` | PASS |
| C1.14 | Streaks, Perfect Day grant / revoke | — | — | locked rules | Auto `streak_rules_test`, `day_completion_test` (full suite) | PASS |
| C1.15 | Minimum Day on / undo; no Perfect Day on Minimum Day | today | activate / return | today only, reversible | Auto `phase10a_flow_test`, `phase11e_notifications_test` (not repeated on the device in this phase) | PASS |
| C1.16 | Achievements: 32, 0 XP, today's reconcile, history immutable | — | — | locked rules | Auto `phase10c_catalog_test`, `achievement_*` (core set) | PASS |
| C1.17 | Target edits affect future dates only | Arc | edit Water target | from next day | Auto `habit_edit_timing_test`, `hydration_planner_test` | PASS |
| C1.18 | Clock moved back a day | Day 2 with data | resume on Day 1 | Day 1 shown, Day 2 rows unchanged, no crash | Auto `phase11e_lifecycle_test`; Device E21 | PASS |
| C1.19 | Time-zone change to before Day 1 | Arc starting today | zone change while backgrounded | "Starts tomorrow", tracking disabled, no crash | Device E22; Auto `date_edges_test` | PASS |

### C2. Smart Hydration

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C2.1 | Off by default; no Arc; no built-in Water; custom "Water"; renamed Water | — | — | locked contract | Auto `phase11b_hydration_flow_test`, `hydration_planner_test`, `hydration_service_test` | PASS |
| C2.2 | Permission denied | not granted | turn on, deny real prompt | stays off, explained, 0 alarms | Device E5 | PASS |
| C2.3 | Permission granted | — | turn on, allow | 7 days × 4 (Balanced) = 28 inexact `RTC_WAKEUP` alarms, no exact alarm | Device E5 | PASS |
| C2.4 | Deterministic checkpoints | window 00:30–08:30 | — | bases 01:42 / 03:42 / 05:42 / 07:42, each ±15 min | Device E5 (01:53, 03:37, 05:54, 07:38) | PASS |
| C2.5 | Real delivery and tap | behind pace | checkpoint passes | "Hydration check", channel `hydration_coach`, tap → Today | Device E12, E13 | PASS |
| C2.6 | Logging Water re-plans; ahead of pace suppresses | 1 glass | log to 4 | only the 4-glass checkpoint removed | Device E14; Auto `phase11e_notifications_test` | PASS |
| C2.7 | Minimum Day on / undo | — | — | today's nudges go / return | Auto `phase11e_notifications_test`, 11B flow | PASS |
| C2.8 | Midnight / date rollover | open | cross midnight | new day planned, ids mean the new date | Device E16; Auto `phase11e_lifecycle_test` | PASS |
| C2.9 | Mode limits 3 / 4 / 5; window 8–18 h | — | — | locked | Auto `hydration_planner_test` | PASS |
| C2.10 | Disabling cancels pending | on | turn off | 0 alarms (others off) | Device E27 | PASS |
| C2.11 | Restore turns it off, keeps window and mode | on | restore | off, kept | Device E19; Auto `phase11e_restore_test` | PASS |
| C2.12 | Cap with everything on | all reminders, Supportive | — | ≤ 63 pending | Auto `phase11e_notifications_test`, `hydration_planner_test`; Device 56 pending | PASS |

### C3. Focus Guard

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C3.1 | Off by default; switch needs access + apps | fresh | open settings | disabled, explained | Device E6 | PASS |
| C3.2 | Usage Access granted (real switch) | — | tap Allow, toggle | `GET_USAGE_STATS: allow` for the test package only; "Allowed" on return | Device E6 | PASS |
| C3.3 | Picker: launcher only, search, two apps | access | choose | 2 chosen, no `QUERY_ALL_PACKAGES` | Device E6 | PASS |
| C3.4 | Budget valid / invalid | — | 0, 1441, 1 | invalid refused, 1 saved | Device E6 | PASS |
| C3.5 | Uninstalled app, removal, 100 max | — | — | locked | Auto `phase11c_focus_guard_flow_test`, `focus_guard_service_test` | PASS |
| C3.6 | Below / at / over budget | — | — | none / one / one | Auto JVM `FocusGuardCheckTest`; Device E7 ("Budget reached") | PASS |
| C3.7 | Real natural nudge | over budget | wait for WorkManager | one notification `focus_guard` / tag `focus_guard` / id 1 | Device E8 (00:53:48, `:focus_guard` process) | PASS |
| C3.8 | No second nudge that day | claimed | later natural runs | nothing posted | Device E9 (01:08, 01:23, 01:38 runs) | PASS |
| C3.9 | Next local day eligible | Day 2, over budget | natural run | one new nudge | Device E18 (01:34:38) | PASS |
| C3.10 | Tap backgrounded / after process death | nudge shown | tap | Today | Device E18 (cold, new pid); 11C warm evidence; Auto flow | PASS |
| C3.11 | Usage Access revoked while on | on | real switch off, resume | "paused", job cancelled, card never "0 min" | Device E23 | PASS |
| C3.12 | Notifications denied / regranted | on | revoke, relaunch, grant | no crash; "Notifications are off"; recovers | Device E24 | PASS |
| C3.13 | `focus_guard` channel blocked | on | block channel only | Focus Guard "Off", reminders unaffected | Device E25 | PASS |
| C3.14 | Settings change / off during a check; concurrency; claim forward-only | — | — | claim lost / never released | Auto JVM (67), `focus_guard_persistence_test` | PASS |
| C3.15 | WorkManager survives process death; no duplicate job | on | kills | one unique work id | Device E9, E10 | PASS |
| C3.16 | Reboot | on | reboot, app not opened | job back | Device E20 | PASS |
| C3.17 | Force-stop / reopen | on | force-stop, open | job gone / back | Device E20 | PASS |
| C3.18 | Restore leaves it off, job cancelled, apps and budget kept, nudge date NULL | on | restore | as stated | Device E19; Auto `phase11e_restore_test` | PASS |
| C3.19 | Re-enable after restore: narrow exception | restored | turn on | one more nudge possible that day | Device E19 (01:39:17); Auto `phase11e_restore_test` | PASS |
| C3.20 | Absent on iOS | iOS | — | no card text, no entry, no job | Sim `phase11e_ios_smoke_test`; Auto 11C | PASS |
| C3.21 | Disabling cancels job | on | turn off | 0 jobs | Device E27 | PASS |
| C3.22 | Budget tile at large text | budget "1 h 30 min" | 2× text, 360 dp | title readable | **Defect D1 found and fixed**; Device E26; Auto `phase11e_layout_test` | PASS (after fix) |

### C4. Hydration + Focus Guard + reminders together

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C4.1 | Independent settings | both on | change either | the other's settings untouched | Auto `phase11e_notifications_test`, combined flow | PASS |
| C4.2 | Channels distinct | all families | — | `daily_reminder`, `reflection_reminder`, `hydration_coach`, `focus_guard` | Device E11, E18; Auto notifications | PASS |
| C4.3 | Ids never overwrite | all shown | — | (null, 100…364) vs (`focus_guard`, 1) | Device E11 (FG + 100 + 200), E18 (FG + 100 + 200 + 300) | PASS |
| C4.4 | Reconciliation never removes a shown notification | FG nudge + hydration shown | Water, Minimum Day, settings, off, restore, new process | still shown; plugin `cancelAll` never called | Auto `phase11e_notifications_test` (real `LocalNotificationScheduler`) | PASS |
| C4.5 | Routing per payload in every Arc state | — | taps | daily/hydration/FG → Today, reflection → Journal; stale → home | Device E10, E11, E13, E18; Auto notifications + `app_routes_test` | PASS |
| C4.6 | Same day, background, process death, permission changes, midnight, resume, restore | both on | — | both behave | Device E8–E25; Auto lifecycle | PASS |

### C5. Manual update check

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C5.1 | Zero requests without a tap | — | launch, onboarding, setup, Today, Journal, History, Insights, Reminders, Hydration, Focus Guard, WorkManager, resume, midnight, backup, restore, About open / rebuild / leave / reopen, share, reboot | app UID 0 bytes | Device per-UID `netstats` at every step; Auto `phase11e_*` (fake GitHub counts 0), 11D flow | PASS |
| C5.2 | One request per tap | About | tap | 1 request; "latest published v1.1.0" | Device E11 (0 → 9,236 rx / 975 tx); Auto | PASS |
| C5.3 | Single-flight, no retries, timeout, size, redirects, validation | — | — | locked | Auto `github_release_feed_test`, `update_checker_test`, 11D flow | PASS |
| C5.4 | Update available (synthetic v1.2.0) → official page only | fake feed | tap, View official release | official tag page | Auto `phase11e_combined_flow_test` | PASS |
| C5.5 | External browser only | About | Open on GitHub | Chrome task; app UID unchanged | Device E28 | PASS |
| C5.6 | iOS: no check | iOS | About | version, no button, 0 HTTP clients | Sim | PASS |

### C6. Database, backup and restore

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C6.1 | Migrations v1 → … → v6, v5 → v6 | fixtures | — | data preserved, opt-ins off | Auto migration set | PASS |
| C6.2 | Formats 1, 2, 3 restore with everything on | all on | restore each | reminders, Hydration, FG off; FG apps/budget only from format 3 | Auto `phase11e_restore_test` | PASS |
| C6.3 | Cross-feature restore scenario (section 16) | everything on, real file | export, change, restore, relaunch | all data back; opt-ins off; no nudge possible; no HTTP client; healthy file | Auto `phase11e_restore_test` | PASS |
| C6.4 | Restore under a held write lock | another connection writing | restore | fails whole; nothing replaced or cancelled; succeeds later | Auto `phase11e_restore_test` (real SQLite file; macOS and Linux CI) | PASS |
| C6.5 | Device export (SAF), cancel, restore | device | picker save, cancel, restore | file format 3; cancel silent; restore contract | Device E19 | PASS |
| C6.6 | One DB file, schema 6, integrity, journal `delete`, no `android_metadata` | after device run | inspect | as stated | Device E29 | PASS |
| C6.7 | Corrupt, invalid, unsupported files, failed save | — | — | refused, nothing changed | Auto backup set, `phase5_flow_test` | PASS |

### C7. Privacy, permissions, builds and platforms

| ID | Feature / interaction | Precondition | Action | Expected result | Evidence | Result |
|---|---|---|---|---|---|---|
| C7.1 | Release permissions exactly the approved 7 | release APK | aapt2 | exact set, none forbidden | [O](#o-android-build-evidence) | PASS |
| C7.2 | Components | release APK | xmltree | provider not exported; no FGS, WebView, a11y, VPN, listener | [O](#o-android-build-evidence) | PASS |
| C7.3 | R8 constructors kept; minified startup | release APK | apkanalyzer; launch | kept; no crash | [O](#o-android-build-evidence), Device E2 | PASS |
| C7.4 | No analytics / ads / telemetry / token / logs of data | source | audit | none | [L](#l-privacy-and-security-audit) | PASS |
| C7.5 | iOS builds | — | build | pass | [Q](#q-ios-build-and-simulator-evidence) | PASS |
| C7.6 | UI at 2×, 1.3×, 1.5×, landscape, tablet, reduced motion | integrated screens | scroll every screen | no overflow | Auto `phase11e_layout_test` (87); Device landscape E28 | PASS |
| C7.7 | Physical device | — | — | — | **NOT RUN — DEFERRED TO PHASE 11F** | NOT RUN |
| C7.8 | Human TalkBack / VoiceOver pass | — | — | — | not required (existing contract) | NOT RUN |

### Counts

80 rows: **78 PASS** (one, C3.22, after fixing D1), **2 NOT RUN** (C7.7
physical device, deferred to Phase 11F; C7.8 human TalkBack / VoiceOver,
non-blocking), **0 FAIL**, **0 BLOCKED**, 0 NOT APPLICABLE. Device rows
that were not repeated in this phase (e.g. E15) point to their automated
evidence; their device evidence is in the earlier phase records.

## D. Cross-feature scenarios (automated)

New suites in `test/integration/` (all CI, no network or device):

| File | Tests | What crosses subsystem boundaries |
|---|---|---|
| `phase11e_restore_test.dart` | 3 | section 16 on a **real SQLite file**: completed + active Arc, Water, XP, achievements, reflection, daily + reflection + Hydration (Supportive), Focus Guard (2 apps, 45 min, today claimed by the **Kotlin claim SQL**) → export format 3 → change everything → restore → every user row identical, opt-ins off with settings kept, `last_nudged_on` NULL, job cancelled, the worker's claim now matches nothing, **no `HttpClient` created** (`HttpOverrides`), relaunch on the same file (`integrity_check`, `foreign_key_check`, `user_version` 6), then the documented re-enable exception; formats 1, 2 and 3 over a device with everything on; restore while another connection holds the write lock (fails whole, nothing cancelled, succeeds afterwards) |
| `phase11e_notifications_test.dart` | 6 | the **real `LocalNotificationScheduler`** over an emulated Android plugin channel that tracks pending alarms *and* shown notifications by (tag, id): four channels, disjoint ids, ≤ 63; no reconciliation, Minimum Day, settings change, empty plan, restore or new process removes a shown hydration, daily or Focus Guard notification (`cancelAll` never called); idempotent reconcile, same set after a new process; Water / Minimum Day / Focus Guard changes touch only their own; permission denied and regranted; routing table for 6 payloads × 4 Arc states |
| `phase11e_lifecycle_test.dart` | 7 | whole app with everything on: midnight while open; background day change and process death (one re-plan, one tap handler); Day 92 → 93 (Arc closes, reminders stop, Focus Guard stays on, stale taps → summary, About offline until tapped); clock moved back; restore from the running app (one tap handler, one reconcile per resume); About across midnight; DST / leap-day / month and year ends |
| `phase11e_combined_flow_test.dart` | 1 | section 19's 34 steps through the real UI on a real file: onboarding → Rolling Arc → habits, XP → reflection → Hydration (Supportive) → Focus Guard (access, two apps, 30 min) → Water re-plan → card `18 / 30 min` → About (1.1.0, 2; one request; synthetic v1.2.0 → official page) → background / resume → export → restore → relaunch; exactly **one** GitHub request overall |
| `phase11e_layout_test.dart` | 87 | 11 screens × 6 layouts (65 cases: Insights at 2× excluded, see N) (360 × 800 at 2×, 320 × 568 at 1.5×, 568 × 320, 800 × 360 at 1.3×, 1280 × 800, 360 × 640 at 1.3× with reduced motion), each scrolled top to bottom, plus the D1 regression (11 budgets × 1× and 2×) |
| `integration_test/phase11e_ios_smoke_test.dart` | 1 | iOS simulator smoke with the real plugins (not run in CI; see Q) |

Support: `test/support/focus_guard_worker.dart` runs the worker's claim
statement extracted from `FocusGuardStore.kt`.

## E. Smart Hydration qualification

- Device (minified build): denial keeps it off with the explanation and 0
  alarms; allow plans **28** alarms (7 × 4, Balanced) as inexact
  `RTC_WAKEUP` (`window=+1h`, no `exactAllowReason`). Window 00:30–08:30:
  01:53, 03:37, 05:54, 07:38 = bases 01:42 / 03:42 / 05:42 / 07:42 within
  ±15 min.
- Delivery: id 300 at 01:54:46 for 01:53 (channel `hydration_coach`, "Hydration
  check" / "A little water now can keep you on pace."); tap → Today.
- Water 1 → 4 at 01:55 removed only the 03:37 checkpoint (expects 4).
- After midnight: 17 Oct planned 01:27 / 03:43 / 05:57 / 07:42 (new
  deterministic times), 7-day horizon moved.
- With daily + reflection + hydration on: **56** pending (14 + 14 + 28),
  within 63.
- Restore: off, window and mode kept, **0** alarms. Turning it off: 0.

## F. Focus Guard qualification

- Real Usage Access grant / revoke on the system page, only for the
  qualification package; picker search; budget bounds.
- **Natural** WorkManager run at 00:53:48 in the `:focus_guard` process
  posted exactly one nudge ("You've reached today's 1-minute Focus Guard
  budget. Time to come back to your Arc?", channel `focus_guard`, tag
  `focus_guard`, id 1). Later natural runs at 01:08, 01:23 and 01:38 (one
  unique work id, run in-process by WorkManager while the app was alive)
  posted nothing.
- Day 2: one new nudge (01:34:38); cold-start tap (new pid) → Today.
- Restore: job cancelled, off, apps kept, no notification. Re-enable: the
  documented exception produced one more nudge that day (01:39:17).
- Reboot: job back without opening the app. Force-stop: 0 jobs, 0 alarms,
  `stopped=true`; opening NextRep: both back.
- Revocation: "On, but paused", job cancelled, card "can't be measured".
  Channel blocked: Focus Guard "Off"; reminders unaffected.
- The on-device database after the run: `last_nudged_on = 2026-10-17`
  (see E21 for why), enabled, 1 min, both apps in order.

## G. Manual update-check qualification

Android's per-UID accounting (`dumpsys netstats --poll`, UID stats) for the
qualification package after every step: **0 / 0** through install, launch,
onboarding, About, setup, Today, Journal, reminders, Hydration Coach, Focus
Guard (including WorkManager runs in both processes), backgrounding,
notifications, About left open, resume on About. **One tap** →
**9,236 rx / 975 tx**, "You're using the latest published version. Latest
published: v1.1.0"; unchanged after 20 s idle and on reopening About
(Idle). After the reboot (counters restart), 0 / 0 through restore,
force-stop, revocations, time-zone change, share sheet and Open on GitHub
(Chrome's own UID). No APK in Downloads; no installer. Automated: every new
suite injects a counting fake GitHub (0 requests except the combined flow's
single tap); the restore suite counts `dart:io` `HttpClient` creation (0);
the iOS smoke counts it on the simulator (0).

## H. Notification integration

On the device, at 00:53:48, the Focus Guard nudge, the daily reminder (100)
and the evening reflection (200) were in the shade together; on Day 2,
Focus Guard (tag `focus_guard`, 1), daily (100), reflection (200) and
Hydration (300). None replaced another. Taps: reflection (warm) → Journal;
daily (cold, process killed) → Today; Hydration (warm) → Today; Focus
Guard (cold) → Today. Tapping Focus Guard removed only it (cancel reason
1).

Android observation: with three or more notifications Android groups them
under its own summary (`g:Aggregate_AlertingSection`). Tapping that
*summary* cancels every child (event log reason 12,
`REASON_GROUP_SUMMARY_CANCELED`, by system_server). NextRep cancelled
nothing; individual children tap and route correctly. Not a NextRep
defect.

`cancelAll()` (which would clear the Focus Guard nudge) is never called:
reconciliation only uses `cancelAllPendingNotifications()` and per-id
`cancel` of ids the OS reports as *pending* (asserted in
`phase11e_notifications_test`). No exact alarm (the only
`exactAllowReason` alarm at 01:00 was `com.android.settings`'), no
foreground service.

## I. Database and migration qualification

- Migration set v1 → v6 (CI step): **52 / 52**.
- On the device's real file after the whole run: `user_version` 6,
  `journal_mode` delete, `integrity_check` ok, `foreign_key_check` empty, no
  `android_metadata`, one `app_flutter/nextrep.sqlite` and nothing beside it.
- Locking: a restore that meets another connection holding the write lock
  fails as a whole and leaves every row, the pending reminders and the
  Focus Guard job as they were; it succeeds once the lock is released
  (`phase11e_restore_test`, real SQLite file, on macOS and on Linux CI).
- Not established here: whether Drift *waits out* a short lock. Drift's
  transactions begin with `BEGIN IMMEDIATE` (drift 2.35.1) under the 3 s
  busy timeout from Phase 11C; an in-process model of the worker's lock
  waited on macOS but failed at once on Linux CI (the first CI run of this
  PR), so it says nothing reliable about Android's cross-process case. That
  test was removed rather than weakened, and Phase 11C's documented locking
  limitation stands as written. Either way a lost race fails safely and the
  user can retry.
- Real v5 → v6 on a production install: Phase 11B on the emulator;
  physical: Phase 11F.

## J. Backup and restore qualification

- Backup set (CI step): **90 / 90** (write 3; read 1, 2, 3).
- Section 16 scenario: [D](#d-cross-feature-scenarios-automated).
- Device: export through the system document picker (`nextrep-backup-
  2026-10-17.nextrep`, 2,911 bytes, format 3, `focusGuard` = budget +
  package names only, reminders = times only); cancelled picker silent;
  restore with everything on → Water back to the backup's value, reminders
  and Hydration off (times, window, mode kept), Focus Guard off (apps kept),
  0 alarms, 0 jobs, no notification, 0 bytes. The file was deleted from the
  emulator afterwards and never left the scratch area.

## K. Date and lifecycle qualification

Automated (deterministic clocks): midnight while open, background day
change, process death, Day 92 → 93, month and year ends, leap day
(2028-02-29), clock moved back, DST days. The full suite also ran under
`TZ=America/New_York` (**1248 / 1248**) and the date-sensitive and Phase 11E
suites under New York, London, Lord Howe (30-minute DST) and UTC
(**153 / 153** in each zone).

Device: rollover while open (after re-arming on resume; a wall-clock jump
made *while* in the foreground is only seen at the next resume, as
recorded in Phase 11C); clock moved back ~23.5 h (Day 1 restored, no
crash); time zone changed to America/New_York while backgrounded ("Starts
tomorrow", tracking disabled) and back; reboot; force-stop; process kill;
background / resume; notification taps warm and cold; document picker;
share sheet; Chrome; landscape.

## L. Privacy and security audit

- `pubspec.lock`: no analytics, advertising, crash-reporting or remote
  config SDK.
- Dart: only `github_release_feed.dart` does HTTP (static boundary test);
  no `print` / `debugPrint`; `ErrorReporter` uses `dart:developer` (no-op in
  release); no token, key or bearer string. Kotlin: only `Log.d` of the
  check's outcome name, debuggable builds only; no network API.
- iOS: no entitlements file, no URL session code, no `Info.plist` change.
- PRIVACY.md, README and About already describe the integrated behaviour
  (offline, opt-in update check, Usage Access, package names in backups,
  restore turns opt-ins off). No change needed.
- Fixtures and tests use `org.example.*` only. The device run used two stock
  emulator apps (Settings, Clock); no device inventory, log or backup is
  committed.

## M. Performance observations

- Minified cold start 1.39 s on the emulator (`am start -W`), warm ~0.8 s.
- Per resume: exactly one reminder reconciliation and one Focus Guard
  reconciliation (`phase11e_lifecycle_test`), including after a restore.
- A Water log reschedules only changed hydration ids (diffing).
- Focus Guard: one unique periodic work; runs took 62–185 ms
  (WorkManager start → result).
- No repeated provider initialization or listener leak found (tap-handler
  count stays 1 across restore and relaunch).

No performance defect was found; nothing was optimised.

## N. Accessibility and UI review

`phase11e_layout_test` scrolls Today, Journal, History, Reminders, Focus
Guard settings, the app picker, Data & Backup, About (idle and with an
available update), Insights and a completed Arc's summary with long names,
every feature on and Focus Guard over its budget, in six layouts. One
defect (D1) was found and fixed. Device: 2× font at 360 dp (D1 before and
after), landscape Today and share preview (Share reachable by scrolling),
Insights at 2× (fine with the real font).

Excluded on evidence: Insights' mood breakdown at 2× overflows only with
the test font's square glyphs; on the device at 2× / 360 dp it fits. Not a
product defect (unchanged since Phase 7); its other layouts stay in the
sweep. Human TalkBack and VoiceOver passes: not run (non-blocking).

## O. Android build evidence

Final code, worktree without `key.properties` (debug-signed; never
distributable):

| Build | Result |
|---|---|
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS, 66,360,261 bytes, `com.nextrep.nextrep` 1.1.0 (2), signer `CN=Android Debug` (`5317210b…167d`) |
| Release permission and component audit (the CI step's logic) | PASS |

Release manifest (`aapt2`, `apkanalyzer`):

| Check | Result |
|---|---|
| Package / version | `com.nextrep.nextrep`, versionName 1.1.0, versionCode 2, min 24, target 36 |
| Permissions, exactly | `INTERNET`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `PACKAGE_USAGE_STATS`, `WAKE_LOCK`, `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| Forbidden (19 checked) | none present |
| Exported | `MainActivity` (launcher); `SystemJobService` (`BIND_JOB_SERVICE`); `DiagnosticsReceiver`, `ProfileInstallReceiver` (`DUMP`) |
| Focus Guard provider | present, `exported=false`, `:focus_guard` |
| Absent | Accessibility, VPN, notification-listener services; `SystemForegroundService` / `foregroundServiceType`; `WebViewActivity` |
| R8 | `WorkDatabase_Impl <init>()`, `FocusGuardWorker <init>(Context, WorkerParameters)`, `FocusGuardCheckProvider <init>()` kept |

## P. Android emulator evidence

`emulator-5554`, `sdk_gphone64_arm64`, Android 16 (API 36), 1280 × 2856 at
480 dpi, Asia/Kolkata. 16–17 Oct 2026.

**Official install protected.** `com.nextrep.nextrep` (UID 10253, v1.1.0
(2), first installed 2026-10-12 22:38:38, updated 22:39:16, signer
`65b70cd0…f0ba`, APK SHA-256 `3775470e…00f5`) was recorded first and
compared at the end: identical record, byte-identical APK, Usage Access
untouched, 0 bytes. Its process was running since the emulator booted
(its own boot receiver), not started by this phase. Every build was
installed as `com.nextrep.nextrep.qualification` (temporary, uncommitted
`applicationIdSuffix`, debug-signed), uninstalled at the end.

**Builds under test:** minified release `d0101fa1…` (the phase's test
code, before D1); the installed APK's SHA-256 matched the build. After the
D1 fix, `a5fbd7dc…` (final source, minified) was installed in place and
re-checked (launch, no FATAL, D1 at 2× and 1×). The first D1 attempt
(`37c21daf…`) was installed the same way and rejected on the device (see
T). A debug build of the same
source read the database (E29).

| # | Step | Result |
|---|---|---|
| E1 | Install beside the official app | Success; UID 10257; official unchanged |
| E2 | Cold launch, minified | onboarding; `TotalTime` 1391 ms; no FATAL / R8 error; 0 bytes |
| E3 | About from onboarding; Rolling Arc | Version 1.1.0 Build 2, Idle, 0 bytes; Day 1 of 92, 16 Oct 2026 – 15 Jan 2027 |
| E4 | Habits, Water, reflection | 15 XP, 1/8 glasses, reflection saved |
| E5 | Hydration: deny, window, allow | see [E](#e-smart-hydration-qualification) |
| E6 | Focus Guard: access, picker, budget, on | see [F](#f-focus-guard-qualification); 1 job, first run immediate |
| E7 | 80 s in Clock | card "1 of 1 minutes used today. Budget reached." |
| E8 | Natural nudge | 00:53:48, `:focus_guard` pid |
| E9 | Later natural runs | 01:08, 01:23, 01:38; nothing posted |
| E10 | Process killed (`am kill`) | job kept, one work id |
| E11 | Three families together; About live check | FG + 100 + 200; tap check → 9,236 / 975 bytes |
| E12 | Hydration delivered (clock moved to 01:52:30, `auto_time` off) | id 300 at 01:54:46 |
| E13 | Taps | reflection warm → Journal; daily cold → Today; hydration warm → Today |
| E14 | Water re-plan | 03:37 removed only |
| E15 | Minimum Day | NOT RUN on the device in this phase (automated: `phase10a_flow_test`, `phase11e_notifications_test`; device: Phase 11B) |
| E16 | Midnight while open | Day 1 → Day 2 (Saturday 17 October); plan moved; Journal "TODAY · DAY 2" |
| E17 | Backgrounded day change (clock moved while paused) | Day 2 on resume |
| E18 | Day 2 together; cold FG tap | FG + 100 + 200 + 300; FG → Today (new pid) |
| E19 | Export (SAF), cancel, restore, re-enable | see [J](#j-backup-and-restore-qualification); exception nudge 01:39:17 |
| E20 | Reboot; force-stop | 26 alarms + 1 job after boot; force-stop 0 / 0, reopen 26 / 1 |
| E21 | Automatic time restored (clock back ~23.5 h) | Day 1 shown, data intact, plan from 16 Oct; the claim recorded under the forward clock (`2026-10-17`) counts as already nudged |
| E22 | Time zone → America/New_York while backgrounded, and back | "Thursday, 15 October / Starts tomorrow", tracking disabled; back to Day 1 |
| E23 | Usage Access revoked / regranted (real switch) | paused, job cancelled / job back |
| E24 | Notifications revoked / regranted | process killed by Android, cold relaunch, notices shown / cleared |
| E25 | `focus_guard` channel blocked / restored | FG "Off" / "On"; reminders unaffected |
| E26 | D1 at 2× / 360 dp (`font_scale` 2.0, density 569) | before: title broken mid-word; after: whole words, value under it; 1×: unchanged |
| E27 | Hydration and Focus Guard off | 0 alarms, 0 jobs |
| E28 | Landscape, share sheet, Open on GitHub | share preview scrolls to Share; sheet and back; Chrome task; 0 app bytes |
| E29 | Debug build over release (same signer), `run-as` | see [I](#i-database-and-migration-qualification) |
| E30 | Cleanup | uninstalled; backup file deleted; automatic time and zone, Asia/Kolkata, font 1.0, density 480 restored; no alarm or job left |

Notes (test artifacts, not defects):

- Moving the clock forward fires overdue `RTC` alarms at once: two of Day
  1's checkpoints (05:54, 07:38) posted at 23:59:40 when the clock jumped
  over them.
- WorkManager schedules periodic work from wall-clock timestamps: after the
  clock went back ~23.5 h, the restored job's next run was 23 h 52 min
  away, until the regrant re-enqueued it (15 min). A best-effort delay
  caused by a manual clock change; real midnights and zone changes don't
  move epoch time. Documented in [V](#v-remaining-limitations).
- The emulator's `accelerometer_rotation` was set to 0 for the landscape
  check; its earlier value wasn't recorded (rotation is back to portrait).

## Q. iOS build and simulator evidence

| Check | Result |
|---|---|
| `flutter build ios --simulator` | PASS |
| `flutter build ios --release --no-codesign` | PASS (22.3 MB) |
| `integration_test/phase11e_ios_smoke_test.dart`, iPhone 17 simulator, iOS 27.0 | **PASS**: fresh install → Rolling Arc → No Junk Food (15 XP) and Water → Hydration Coach section present, turning on without permission explains and stays off → no Focus Guard text anywhere, no History entry → Data & Backup (Export, Restore) → About **Version 1.1.0, Build 2** from the real `Info.plist`, no Check for updates → **0 `HttpClient`s** |
| `phase11d_about_smoke_test`, `day_one_smoke_test`, `phase7_release_smoke_test` on the same simulator | PASS / PASS / PASS |
| iOS notification delivery | NOT RUN (the smoke avoids the system permission prompt; covered by platform-neutral tests) |
| `ios/` changes, entitlements | none |

## R. Physical device status

**PHYSICAL DEVICE: NOT RUN — DEFERRED TO PHASE 11F.** The owner's OnePlus
CPH2707 (official signed v1.1.0) was not connected (`adb devices` listed
only `emulator-5554`) and was not touched. No emulator result here is a
physical result, and the historical v1.0.0 → v1.1.0 physical evidence is
not used for v1.2.

## S. Confirmed defects

| ID | Severity | Defect | Root cause | Contract affected |
|---|---|---|---|---|
| D1 | P2 | Focus Guard settings: at 2× text on a 360 dp phone, a budget shown as hours and minutes (the "1 h 30 min" preset, and others up to "23 h 59 min") took most of the budget row; "Combined daily budget" broke mid-word ("Combi / ned"), and in debug builds `ListTile` asserted "Trailing widget consumes the entire tile width". | `_BudgetCard` put an unbounded value in `ListTile.trailing` (Phase 11C) | Phase 7's text-scale bar (2× on a phone) |

No P0 or P1 defect was found. No defect required a schema, backup format,
permission, signing or architecture change.

Investigated and **not** defects (evidence above): Android's group-summary
tap cancelling children; overdue alarms after a forward clock jump;
WorkManager's wall-clock deferral after a backward jump; in-process
WorkManager runs not appearing in JobScheduler's history; Insights at 2×
with the test font; the official app's boot-started process.

## T. Fixes implemented

- **D1** (`lib/features/focus_guard/focus_guard_settings_screen.dart`):
  above 1.3× text, the budget value moves from `trailing` to its own line
  under the subtitle, so the title has the row; at normal sizes the tile is
  unchanged. Semantics label unchanged. A first attempt (capping the
  trailing width) passed the widget test but still broke the title and
  clipped the wrapped value on the device; it was replaced before commit.
- Regression: `phase11e_layout_test.dart`, "Focus Guard budget … keeps its
  label whole": 11 budgets (1 min to 24 h, every preset) at 1× (value
  beside the title) and 2× (value under a title at least 200 px wide, no
  exception). All 11 2× cases fail without the fix. Re-qualified on the
  device in the minified build (E26).

## U. Automated test results

All on the final source, locally (Flutter 3.47.5 / Dart 3.13.4):

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 304 files, 0 changed |
| `flutter analyze` | no issues |
| `flutter test` | **1248 / 1248** (1144 at baseline + 104 new; none removed, skipped or weakened) |
| `./gradlew :app:testDebugUnitTest` | **67 / 67** (unchanged) |
| Migrations v1 → v6 (CI step) | 52 / 52 |
| Backup formats (CI step) | 90 / 90 |
| Focus Guard (CI step) | 104 / 104 |
| Manual update check (CI step) | 182 / 182 |
| Release qualification (CI step) | 39 / 39 |
| Hydration and reminders (planner, service, reminders, 11B flow) | 82 / 82 |
| Core Arc, habits, XP, achievements, Minimum Day (17 files) | 223 / 223 |
| Phase 11E integration (`test/integration/`) | 104 / 104 |
| `TZ=America/New_York flutter test` | **1248 / 1248** |
| Phase 11E + date suites under New York, London, Lord Howe, UTC | 153 / 153 each |
| iOS simulator integration smokes (4) | PASS |

CI adds the Phase 11E suites through its existing "All tests" step.

## V. Remaining limitations

- Focus Guard and Hydration timing are best effort (Doze, standby,
  Android 16's `FLEXIBILITY`); unchanged contract.
- A manual wall-clock change has edge effects: overdue reminders fire at
  once after a forward jump; after a large backward jump WorkManager may
  wait until the wall-clock period recorded before the jump has passed
  (observed 23 h 52 min); a claim made under a clock set ahead counts as
  "already nudged" for that date (forward-only rule). Time-zone changes and
  real midnights don't do this.
- Tapping Android's automatic group summary clears all of NextRep's shown
  notifications (Android behaviour).
- iOS notification delivery and Hydration Coach with a granted permission
  were not exercised on the simulator.
- No physical device; no human TalkBack / VoiceOver pass.

## W. Phase 11F handoff requirements

Prerequisites passed here: the integrated source qualifies (matrix above),
the release permission and component audit passes, the minified build
starts and runs Focus Guard, Hydration Coach, reminders, About, backup and
restore on API 36, iOS builds and smokes pass, CI is green on the PR head.

Phase 11F must still, in order:

1. Bump to **1.2.0+3** and set `appVersion` to `1.2.0` (the `app_info`
   test keeps them equal); write `docs/releases/v1.2.0.md`.
2. `flutter clean`; `tool/release/prepare_android_release.sh` in the main
   checkout with the permanent key: signer `65:B7:0C:D0:…:F0:BA`
   (`65b70cd0…f0ba`), `com.nextrep.nextrep` 1.2.0 (3), exact permission set,
   component and R8 checks, staged APK and `.sha256`; byte-identical across
   two clean builds.
3. Physical OnePlus CPH2707: export a backup from the official v1.1.0
   first; `adb install -r` of the signed v1.2.0; `firstInstallTime`
   unchanged, same signer; the **real v5 → v6 migration**; data identical
   to the pre-update backup; Hydration Coach and Focus Guard **off** after
   the update; reminders as they were.
4. Physical smoke: Focus Guard (Usage Access, one natural nudge, revoke),
   Hydration Coach delivery, notification taps, About and **one** manual
   check (expect "latest published: v1.1.0" before publishing), backup and
   restore, force-stop / reboot. Measure per-UID bytes as in G.
5. Publish: tag `v1.2.0`, full (not pre-) GitHub Release with
   `NextRep-v1.2.0-android.apk` and `.sha256` uploaded, then confirm an
   installed v1.1.0 cannot check (no `INTERNET`) and the v1.2.0 build
   reports "latest published: v1.2.0".

Known risks for 11F: WorkManager / Android 16 deferral on the OnePlus (run
the nudge over a natural period, as here); the official v1.1.0 → v1.2.0
in-place update is the first time a production database meets schema v6 on
a phone; the first real "update available" can only be seen after
publication.

## X. Final qualification verdict

Every gate in section 33 passes or is honestly not run:

| Gate | Result |
|---|---|
| Format / analyze / full Flutter suite / native JVM | PASS (304 files, 0 changed / no issues / 1248 / 67) |
| Database migrations / backup compatibility | PASS / PASS |
| Smart Hydration / Focus Guard / manual update check | PASS / PASS / PASS |
| Core Arc lifecycle / XP and achievements / reminder integration | PASS / PASS / PASS |
| Privacy boundary | PASS |
| Android debug build / release build | PASS / PASS |
| Release permission audit / component audit | PASS / PASS |
| Minified Android startup | PASS (executed) |
| Android emulator integration | PASS (executed) |
| iOS simulator build / no-codesign release build / simulator smoke | PASS / PASS / PASS (executed) |
| Physical device | DEFERRED TO PHASE 11F |
| CI on the PR head | recorded in the PR |

One P2 defect (D1) was found and fixed with a permanent regression test;
no P0 or P1 defect remains open. Version, schema, backup format, package
and signer are unchanged.

**Phase 11E qualification passes. Phase 11F may begin after merge.**
v1.2 is not ready for public distribution until Phase 11F completes.
