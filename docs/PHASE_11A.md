# Phase 11A: v1.2 Foundation and Focus Guard Android Feasibility

## Objective

Lock the NextRep v1.2 product architecture and answer one question:

> Can Focus Guard be implemented cleanly on modern Android while
> preserving NextRep's privacy model?

This is a feasibility and foundation phase, **not** a release phase. No
product feature, screen, notification, setting or permission was added
to the app. The Android experiments ran in a temporary, debug-only probe,
which was removed before the final commit (see
[Feasibility probe](#feasibility-probe)).

**Result: FOCUS GUARD: GO** (see [Decision](#go--no-go-decision)).

## Baseline

| | |
|---|---|
| `main` | `7e563e25b7a6b5e0db062d6b98fee709bc05b42e` (PR #14, Phase 10D), clean tree |
| Published | `v1.1.0` GitHub Release (unchanged by this phase) |
| Version | `1.1.0+2` (unchanged) |
| Database schema | **v5** (unchanged) |
| Backup | export `formatVersion` **2**; import reads 1 and 2 (unchanged) |
| Release permissions | `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (unchanged) |
| `flutter test` | 769 / 769 |

## v1.2 scope (locked)

| Pillar | Status for v1.2 |
|---|---|
| A. Smart Hydration | guaranteed |
| B. Focus Guard | conditional on this gate: **GO** |
| C. About + manual Check for updates | guaranteed |

Planned phases: 11B Smart Hydration, 11C Focus Guard, 11D About + manual
update check, 11E integration and polish, 11F v1.2 release qualification
(the only phase that bumps the version to `1.2.0+3`, tags or publishes).

## Smart Hydration contract (Phase 11B, not implemented here)

- Completely optional; off until the user turns it on.
- Follows the authoritative built-in **Water** habit by its stable id, so
  it keeps working when the habit is renamed.
- Paces against **today's effective Water target**, including a Minimum
  Day target, and re-evaluates immediately when Minimum Day is activated
  or undone and whenever Water progress changes.
- Stops, and cancels today's remaining hydration notifications, once
  today's target is complete.
- Behaves like a pacing coach, never a fixed cadence (no "every 15 / 30 /
  60 minutes"). If the user is on or ahead of pace: no notification.
- Modes are **maximums**, not guaranteed counts: Gentle up to 3 nudges a
  day, **Balanced up to 4 (default)**, Supportive up to 5.
- Planned windows may vary slightly per day. The variation is
  deterministic for a given date and configuration, bounded, ordered and
  reasonably spaced, and is never regenerated randomly on resume.
- No medical claims and no computed "water requirement": the Arc's Water
  target stays authoritative.

## Focus Guard contract (Phase 11C)

Focus Guard is **optional** and is **not an app blocker**. It never closes,
blocks, covers or controls another app, intercepts touches, uses an
Accessibility Service, `SYSTEM_ALERT_WINDOW`, a VPN, notification access,
content inspection or browsing history, and never uploads anything or
contacts a backend.

- Off by default. The user explicitly turns it on, picks distracting apps
  and sets **one combined daily budget** across them (e.g. 60 minutes).
  No per-app budgets in v1.2.
- When the selected apps' combined usage today reaches the budget:
  **one** local nudge for that day, e.g. "You've reached today's 60-minute
  Focus Guard budget. Time to come back to your Arc?" No repeats, no
  punishment, no shame copy.
- No XP and no Focus Guard achievements in v1.2.
- A later Today card may show e.g. `38 / 60 min`, `22 min remaining`, and
  a visual state (Shield strong, Near today's limit, Budget reached).
  Visual only: crossing the budget is not a failed day, and tomorrow
  starts fresh.
- Android only. On iOS and other platforms Focus Guard is omitted or
  clearly marked unavailable. No iOS permission or entitlement.

### Focus Guard data policy

- NextRep keeps **no history of app usage**: no per-app, per-day log or
  table. Today's usage is always derived from Android UsageStats when
  needed and is never persisted.
- The only Focus Guard data NextRep will persist is configuration the
  user explicitly chose: enabled state, selected package names, the daily
  budget (and the minimum bookkeeping for "nudged today", a date, never
  an amount).
- App usage is not logged. This record states counts and pass/fail only;
  it contains no app list or personal measurements from the owner's
  phone.

## About + manual update check contract (Phase 11D)

About screen: NextRep, `Version 1.2.0 (3)`, "Your Arc works fully
offline.", GitHub repository (Open repository), Check for updates,
Privacy, Open-source licenses.

The update check is **manual only**:

| Event | Update HTTP requests |
|---|---|
| Cold launch | 0 |
| App resume | 0 |
| Day rollover | 0 |
| Opening About | 0 |
| Tapping "Check for updates" | exactly 1, user-initiated |

- No periodic, launch-time or background checks, no polling, no
  analytics.
- Queries the public GitHub Releases API; no token, API key or secret in
  the app.
- When a newer stable release exists: show the current and the latest
  version and "View update", which opens the GitHub Release page in the
  system browser.
- NextRep never downloads or installs an APK, never requests
  `REQUEST_INSTALL_PACKAGES`, and is not an updater service.
- `INTERNET` is introduced deliberately in Phase 11D, only for that
  button. Until then it remains a CI and release hard fail.

## Privacy and security invariants

- Everything stays on the device. No account, backend, analytics or
  telemetry.
- Usage Access and notification permission are separate. Focus Guard
  measures usage with Usage Access alone; the nudge additionally needs
  notifications, and the UI explains each separately.
- Restoring a backup never turns on anything that can notify, monitor or
  use the network (see [backup format 3](#proposed-backup-format-3)).
- Release builds never contain `QUERY_ALL_PACKAGES`,
  `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, exact-alarm,
  storage, media, contacts, accounts, camera or microphone permissions,
  an Accessibility service, a VPN service or a foreground service.
  `PACKAGE_USAGE_STATS` stays forbidden in release until Phase 11C, and
  `INTERNET` until Phase 11D.

## Android APIs evaluated

| Need | API | Verdict |
|---|---|---|
| Is Usage Access granted? | `AppOpsManager.unsafeCheckOpNoThrow(OPSTR_GET_USAGE_STATS, myUid, packageName)` (API 29+; `checkOpNoThrow` below), falling back to `checkSelfPermission(PACKAGE_USAGE_STATS)` when the mode is `MODE_DEFAULT` | **chosen**; never prompts, < 1 ms |
| Let the user grant it | `Settings.ACTION_USAGE_ACCESS_SETTINGS` with `package:<id>` data | **chosen**; opens NextRep's own "App usage data" page on Android 16 |
| Apps for the picker | `LauncherApps.getActivityList(null, myUserHandle())` plus a `<queries>` intent for `MAIN` / `LAUNCHER` | **chosen**; equals the full launchable set without `QUERY_ALL_PACKAGES` |
| Same, alternative | `PackageManager.queryIntentActivities(MAIN/LAUNCHER)` | equivalent counts; LauncherApps preferred (current user/profile, labels and icons) |
| Today's foreground time | `UsageStatsManager.queryEvents(midnight, now)`, pairing `ACTIVITY_RESUMED` with `ACTIVITY_PAUSED` / `ACTIVITY_STOPPED` per package | **chosen**; includes the session in progress |
| Same, alternative | `queryAndAggregateUsageStats(midnight, now)` → `totalTimeInForeground` / `totalTimeVisible` | rejected; lags until a session ends, then jumps, and buckets may reach before midnight |
| Periodic check | AndroidX WorkManager `PeriodicWorkRequest` (15 min), unique work, `KEEP`, plain `Worker` | **chosen**; no foreground service, no exact alarm, no battery exemption |
| Rejected outright | Accessibility Service, `SYSTEM_ALERT_WINDOW`, `VpnService`, `NotificationListenerService`, foreground service, `QUERY_ALL_PACKAGES`, exact alarms | not needed, not used |

## Feasibility probe

A temporary probe lived only in the debug source set
(`android/app/src/debug/`) while this phase ran, and was deleted before
the final commit. It is preserved in the branch history as commit
`2013edd` ("test: add debug-only Focus Guard feasibility probe"), removed in `7120e16`, for review.

- **Separate package.** The debug build used `applicationIdSuffix
  ".feasibility"` (`com.nextrep.nextrep.feasibility`), so it was installed
  next to, and could never replace or uninstall, the owner's signed
  v1.1.0 on the phone. That install was verified unchanged afterwards
  (`firstInstallTime` 2026-10-08, `lastUpdateTime` 2026-10-12 23:27).
- **Native only.** Kotlin `FocusGuardProbe` (APIs above), a plain
  WorkManager `Worker`, and an adb-driven broadcast receiver. No Flutter
  engine or Dart isolate in the background path.
- **Debug manifest only:** `PACKAGE_USAGE_STATS`, the `<queries>` launcher
  intent, the receiver, and `tools:node="remove"` for WorkManager's
  `FOREGROUND_SERVICE`, `ACCESS_NETWORK_STATE` and
  `SystemForegroundService` (to prove WorkManager runs without them).
- **What it kept:** only non-sensitive diagnostics in a private
  SharedPreferences file (run count, last run time, access yes/no,
  completed yes/no). No usage amount was stored.
- **What it logged:** counts, booleans, timings and, for one explicitly
  injected neutral test app (the system Settings app, driven by adb), its
  foreground seconds. Only deltas are recorded here.

## Usage Access results

| Gate | API 36 emulator | OnePlus CPH2707, Android 16 |
|---|---|---|
| A. No access: detected as unavailable | PASS (`access=false`) | PASS |
| A. Query without access: no crash, but Android returns **0 events, 0 stats, no error** | observed | observed |
| B. Settings intent resolves and opens NextRep's own Usage Access page | PASS (`AppUsageAccessSettingsActivity`) | PASS |
| C. Granted through the real system switch: detected, no restart needed | PASS | PASS (see note) |
| D. Revoked through the real switch: detected on the next check | PASS | PASS |
| D. Process survives revocation (same pid) | yes | yes |
| E. Worker after revocation: no-op | PASS (0 ms) | PASS (2 ms) |
| No crash at any point | PASS | PASS |

Note: on the phone the switch already read On when the probe first opened
the page (it had been turned on at the device moments earlier). The probe
then revoked, re-granted and revoked again through the same switch
(`uiautomator` + tap), each change detected on the next check.

The silent-empty answer and the surviving process are the two design
constraints:

1. An empty UsageStats result means nothing on its own. The gateway checks
   access **before and after** every query and reports "unavailable", never
   "0 minutes" (`TodayUsageReader`).
2. No cached "granted" state may be trusted: access is re-read on every
   use, in the foreground and in the worker.

## UsageStats results

Test app: the system Settings app, brought to the foreground by adb.

| Step | Emulator | OnePlus |
|---|---|---|
| ~60 s session, query after | non-zero, plausible | **+62 s** (events) |
| Second session, query **during** it | events +30 s live; aggregate unchanged | events **+93 s**, live |
| Query after the second session | non-decreasing | **+95 s**; never moved backwards |
| Aggregate stats | caught up only after the session ended | lagged, then jumped (+91 s, then +124 s) |
| Query time | 9–26 ms | 22–41 ms |

**Chosen method:** `queryEvents` from local midnight to now, per selected
package: a session opens on the first `ACTIVITY_RESUMED` while none of the
package's activities is resumed and closes when the last one is paused or
stopped; a session still open at "now" counts up to now, and a package
already in the foreground at midnight counts from midnight. Selected
packages only; the sum is capped at the window (split screen).

**Limitations.** Accurate to seconds in practice, not guaranteed to the
second. The event stream is Android's; a missing event (e.g. a crash)
can skew a session. Picture-in-picture and split screen may count as
foreground. Android keeps events for a few days, which is far more than
"today" needs.

**Day boundary.** The window is computed afresh on every read from the
current zone (`LocalDayWindow`, and `LocalDate.atStartOfDay(zone)` in
Kotlin), so today's total restarts at local midnight and follows a
time-zone change with nothing to reset. Where a zone skips midnight for
DST, the window starts at the first instant that exists.

## App discovery results

| | API 36 emulator | OnePlus Android 16 |
|---|---|---|
| Ground truth (`cmd package query-activities MAIN/LAUNCHER`, shell) | 20 packages | 122 packages |
| `LauncherApps` **without** `<queries>` | **8** (visibility-filtered) | not used |
| `LauncherApps` **with** the `MAIN/LAUNCHER` `<queries>` intent | **20** | **122** |
| `queryIntentActivities` with the same `<queries>` | 20 | 122 |
| Well-known launchable apps present | 3 / 3 checked (the image's Play Store has no launcher entry and is correctly absent) | **8 / 8** checked |
| Internal packages (`android`, System UI, Media provider, Shell, Play services, Phone) | 0 / 5 | **0 / 6** |
| NextRep itself in the list | yes (the picker removes it) | yes (removed) |
| Query time | 21–51 ms | 92–125 ms |
| Same result later (emulator after reboot, phone on a later call) | 20 | 122 |
| `QUERY_ALL_PACKAGES` | absent | absent |

Without a `<queries>` element Android 11+ package visibility hides most
apps from LauncherApps, so **Phase 11C must add the `MAIN/LAUNCHER`
`<queries>` intent** to the main manifest. It grants visibility of apps
that have a launcher entry only, which is exactly the set a user can
pick, and is not `QUERY_ALL_PACKAGES`. Discovery is a live query, so it
reflects installs and uninstalls on the next open; nothing is cached.

## WorkManager results

`androidx.work:work-runtime` 2.10.1, plain `Worker`, unique periodic work,
`KEEP`, 15-minute interval, no constraints.

| Gate | Emulator | OnePlus |
|---|---|---|
| A. One-time worker | PASS, 0–6 ms of work | PASS, 43 ms |
| B. Periodic at the 15-minute minimum | PASS | PASS |
| C. Runs while backgrounded, process killed (`am kill`) after scheduling | **31 runs** from 01:03 to 09:02 (≈ 32 expected) | runs at **+15 m 17 s** and **+15 m 11 s**, each in a new process |
| D. No foreground service, exact alarm, battery exemption, Accessibility, overlay or VPN | PASS (all stripped or absent; not on the Doze allowlist) | PASS |
| E. Access revoked: worker exits as a no-op | PASS | PASS |
| Usage measured with notifications **denied** | n/a | PASS (`notifications=false`, measured) |
| Notifications granted vs denied detected separately | PASS | PASS |

WorkManager's own manifest adds `WAKE_LOCK`, `ACCESS_NETWORK_STATE`,
`FOREGROUND_SERVICE` and `SystemForegroundService`. The probe removed the
last three with `tools:node="remove"` and WorkManager ran normally
without them (no `SecurityException`). **Phase 11C** keeps that removal,
so release would gain only `PACKAGE_USAGE_STATS`, `WAKE_LOCK` (a normal,
install-time permission) and the launcher `<queries>`. The release audit
must then fail on `FOREGROUND_SERVICE`.

**Battery.** Each run is one app-op check and one events query: 0–252 ms
of work per run (phone periodic runs: 165, 252 and 42 ms), every ~15 minutes at best, through the OS's own job batching. No
wake-ups of our own, no exact alarm, no exemption, no foreground service.
The emulator and the phone were on AC power during the runs above.

## Reboot and force-stop

Normal backgrounding is not force-stop. `am kill` (what Android does to a
cached process under memory pressure) leaves the job in place: the
emulator's 31 overnight runs and the phone's runs 3 and 4 each started a
fresh process through `SystemJobService`.

**Reboot (API 36 emulator, twice).** Right after boot the probe's job is
back in JobScheduler (namespace `androidx.work.systemjobscheduler`, only
its timing delay unsatisfied), and WorkManager's `RescheduleReceiver`
received `BOOT_COMPLETED`. NextRep was not opened. No boot hack: this is
WorkManager's own handling through the existing `RECEIVE_BOOT_COMPLETED`.

- After the second reboot the job was ready at 09:32 but did not start:
  Android 16 batches CPU-only jobs (`min_ready_cpu_only_jobs_count=3`,
  `max_cpu_only_job_batch_delay_ms=1860000`, i.e. 31 minutes) and releases
  the batch when it re-evaluates on a system event. On the idle emulator
  it ran at **10:07:11, within a second of an ordinary screen-off**, about
  50 minutes after the previous run, and WorkManager enqueued the next
  period. A real phone has such events constantly (the OnePlus ran on
  time), but the gap shows why the product can promise only "about every
  15 minutes, sometimes later".
- One run (09:17:25) coincided with an adb diagnostic broadcast and is not
  counted as evidence.

**Force-stop (OnePlus).**

| Time | Event |
|---|---|
| 09:44:36 | `am force-stop`: the job left JobScheduler (1 → 0), package `stopped=true` |
| ~09:58:47 | the next slot: **no run** |
| 10:01:37 | the probe's activity came back to the foreground (`next-top-activity`); the package was un-stopped |
| 10:01:39 | WorkManager detected the earlier force-stop, re-enqueued, and ran the overdue work |

A force-stop therefore suspends Focus Guard until NextRep is opened again.
That is Android's rule and NextRep will not work around it (no foreground
daemon, no boot tricks, no other app's help); the Phase 11C settings copy
can say that checks resume when NextRep is opened.

## Permission findings

| Build | Permissions |
|---|---|
| Final release (this PR) | `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`: identical to v1.1.0 |
| Probe debug build (temporary) | the above, plus `INTERNET` (Flutter debug tooling), `PACKAGE_USAGE_STATS`, `WAKE_LOCK` |
| Planned Phase 11C release | v1.1 set + `PACKAGE_USAGE_STATS` + `WAKE_LOCK`, launcher `<queries>`; `FOREGROUND_SERVICE` and `ACCESS_NETWORK_STATE` removed |

## Foundation added

Platform-neutral and unit-tested; no Android library is imported in the
domain, nothing is wired into the app yet, and nothing is persisted.

- `lib/domain/focus_guard/focus_guard_platform.dart`: `UsageAccess`
  (unsupported / notGranted / granted), `LaunchableAppCandidate`, the
  `FocusGuardPlatform` boundary and `UnsupportedFocusGuardPlatform` (iOS
  and tests).
- `lib/domain/focus_guard/today_usage.dart`: `LocalDayWindow`,
  `TodayUsage` (`UsageMeasured` / `UsageUnavailable` with a reason), and
  `TodayUsageReader`: access checked before and after each query, no
  stale value, selected apps only, capped at the window.
- `lib/domain/focus_guard/launchable_apps.dart`: picker list: one entry
  per package, NextRep removed, malformed package names dropped, blank
  labels fall back to the package name, sorted by label.
- `lib/domain/focus_guard/focus_guard_background.dart`:
  `FocusGuardBackgroundScheduler`, a disabled default, and
  `FocusGuardBackground.shouldRun` / `reconcile`: the periodic check
  exists only while Focus Guard is on, access is granted, at least one
  app is selected and a budget is set.
- `lib/data/focus_guard_codec.dart`: decodes platform-channel results;
  fails closed (unknown access → not granted, unreadable usage → error,
  never zero).
- Tests: `test/domain/focus_guard_test.dart`,
  `test/data/focus_guard_codec_test.dart`, fakes in
  `test/support/fakes.dart`.

### Phase 11C architecture

- A Kotlin `FocusGuardUsage` (access check, launcher discovery, the events
  calculation) shared by a MethodChannel handler (for the UI) and a native
  `Worker` (for the background check), with JVM unit tests for the
  session pairing.
- The worker reads its configuration natively (no Dart isolate), exits
  immediately when Focus Guard is off, nothing is selected or access is
  missing, and posts at most one nudge per local day through its own
  notification channel when notifications are enabled.
- `FocusGuardBackground.reconcile` runs at launch, on resume and after
  any change, so revocation or turning Focus Guard off cancels the work.

## Proposed schema v6 (design only)

Schema stays **v5** in this phase. Direction for v1.2:

- `reminder_preferences` (existing singleton) gains hydration columns:
  `hydration_enabled`, `hydration_start_hour`, `hydration_start_minute`,
  `hydration_end_hour`, `hydration_end_minute`, `hydration_mode`
  (gentle / balanced / supportive).
- `focus_guard_preferences` (singleton): `id`, `enabled`,
  `daily_budget_minutes`, `last_nudged_on` (a date, nullable),
  `updated_at`.
- `focus_guard_selected_apps`: `package_name` (primary key),
  `sort_order`, `selected_at`.

Invariants: app-level configuration, not Arc-owned; package names stored
only because the user chose them; **no usage-history table and no per-day
usage log**. If Focus Guard had been NO-GO, v6 would carry no Focus Guard
tables.

## Proposed backup format 3 (design only)

Backups stay **write 2 / read 1 + 2** in this phase. For v1.2: write
**3**, read **1, 2 and 3**.

- Adds the hydration configuration (window and mode) and the Focus Guard
  configuration (budget and selected package names).
- Like reminder times today, **enabled states are not restored**: after a
  restore, hydration nudges and Focus Guard are off until the user turns
  them on again. A restore never starts hydration notifications or Focus
  Guard checks, never asks for Usage Access and never makes a network
  request.
- Selected package names make a v1.2 backup more privacy-sensitive than
  before (they reveal which apps the user wanted to limit). Backups remain
  local, user-controlled files, unencrypted by NextRep; PRIVACY.md will
  say so in Phase 11C.

## Automated validation

On the final tree (`7120e16` + this record). Flutter 3.47.5 / Dart 3.13.4,
JDK 21, build-tools 36.0.0, Xcode 27.

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (258 files, 0 changed) |
| `flutter analyze` | no issues |
| Migration tests (v1 → v5) | 39 / 39 |
| Backup format tests (1 and 2) | 71 / 71 (CI set); 76 / 76 with `phase10c_backup_test` |
| Release qualification tests | 39 / 39 |
| Focus Guard foundation tests (new) | 31 / 31 |
| `flutter test` | **800 / 800** (769 before + 31) |
| `flutter build apk --debug` | PASS (`com.nextrep.nextrep`, no suffix) |
| `flutter build apk --release` | PASS (63.7 MB) |
| Release permission audit (CI list + `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, `FOREGROUND_SERVICE`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, Accessibility / VPN binds) | PASS: none present |
| Release manifest components | no Accessibility or VPN service, no WorkManager, no probe |
| `flutter build ios --simulator` / `--release --no-codesign` | PASS / PASS (21.3 MB) |
| `git diff 7e563e2 -- android ios pubspec.yaml pubspec.lock lib/core/database lib/domain/backup drift_schemas` | empty |

The release permission audit itself (`.github/workflows/flutter-ci.yml`,
`tool/release/prepare_android_release.sh`) is unchanged.

## Limitations

- Best effort: Android may defer the check well beyond 15 minutes
  (batching, Doze, standby buckets, OEM battery management). The copy will
  never promise "every 15 minutes"; the nudge can arrive late.
- After a force-stop nothing runs until NextRep is opened again.
- Usage is Android's accounting, accurate enough for a daily nudge, not to
  the second.
- Physical runs were on AC power; on-battery behaviour on OxygenOS is to
  be watched in Phase 11C qualification.
- Android only.

## GO / NO-GO decision

**FOCUS GUARD: GO**

| # | Criterion | Result |
|---|---|---|
| 1 | Usage Access detected reliably | PASS (both devices) |
| 2 | Grant and revocation handled safely | PASS (real system switch, no restart, no crash) |
| 3 | Today's selected-app usage practically accurate | PASS (+62 s for a 60 s session; live; monotonic) |
| 4 | Useful picker without `QUERY_ALL_PACKAGES` | PASS (122 / 122 with the launcher `<queries>`) |
| 5 | Normal WorkManager background checks | PASS |
| 6 | No foreground service | PASS (WorkManager's removed) |
| 7 | No Accessibility Service | PASS |
| 8 | No overlay | PASS |
| 9 | No VPN | PASS |
| 10 | No backend or Internet | PASS |
| 11 | Revocation → safe no-op | PASS |
| 12 | No long-term usage history | PASS (derived on demand) |
| 13 | Battery acceptable for a best-effort ~15-minute check | PASS (≤ 252 ms per run, OS-batched) |
| 14 | Android 16 physical evidence supports the design | PASS |

## Next phase

Phase 11B: Smart Hydration. Then 11C Focus Guard, 11D About + manual
update check, 11E integration and polish, 11F v1.2 release qualification.
