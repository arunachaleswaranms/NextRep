# Phase 11C: Focus Guard

## Objective

Ship **Focus Guard** as a complete, optional Android feature on the Phase
11A foundation and the Phase 11B persistence: the user picks apps, sets
**one combined daily budget**, and receives **at most one** gentle local
reminder on a day when those apps together reach it. Today shows a card
with today's time against the budget.

Focus Guard is **not an app blocker**. It never blocks, closes, covers or
controls another app, never reads app content, messages, notifications or
browsing, and never uploads anything.

Version stays **1.1.0+2**, schema **v6**, backup format **3**. Nothing was
tagged or published. Phase 11D (About, manual update check, `INTERNET`) was
not started.

## Baseline

| | |
|---|---|
| `origin/main` | `1c7c9cc9dba0a3edbf0836f4691ee8e91f1355e3` (squash merge of PR #16, Phase 11B), verified before any change |
| Merged | PR #15 (Phase 11A), PR #16 (Phase 11B); no open PRs |
| Branch | `phase/11c-focus-guard` from `1c7c9cc`, in a separate worktree (see [Signing safety](#signing-safety)) |
| Version / schema / backup | `1.1.0+2` / v6 / write 3, read 1 + 2 + 3 |
| `flutter test` | 902 / 902 |
| Existing Phase 11C code | none (only the 11A foundation and the 11B persistence) |

## Reused, not rebuilt

| From | Used as |
|---|---|
| 11A `FocusGuardPlatform`, `UsageAccess`, `LaunchableAppCandidate`, `UnsupportedFocusGuardPlatform` | the Dart boundary; Android implements it, iOS and tests keep the unsupported default |
| 11A `TodayUsageReader`, `LocalDayWindow`, `TodayUsage` | the only way the app measures today (access before and after, no stale value, capped at the window) |
| 11A `LaunchableApps.forPicker` | the picker list (NextRep removed, one per package, validated names, label fallback, sorted) |
| 11A `FocusGuardBackground.shouldRun` / `reconcile` | the only decision whether the periodic job exists |
| 11A `FocusGuardCodec` | fail-closed decoding of every channel result |
| 11A Kotlin probe (`2013edd`) | the qualified AppOps check, settings intent, LauncherApps query and event pairing, rewritten as production code |
| 11B `focus_guard_preferences`, `focus_guard_selected_apps`, `DriftFocusGuardSettingsRepository`, `FocusGuardRules` | the single store of settings for the UI **and** the worker; budget 1–1440 (default 60), ≤ 100 apps |
| 11B backup format 3 `focusGuard` section and restore | unchanged; restore already stores Focus Guard off with no nudge |

Small, documented adjustments:

- `FocusGuardPlatform.nudgesAllowed()`: the UI needs the same "can the
  nudge appear" answer the worker uses (app notifications **and** the
  `focus_guard` channel not blocked), which `ReminderScheduler` can't give.
- `FocusGuardSettings.copyWith`, and `save()` no longer writes over a
  stored `last_nudged_on` (see [Concurrency](#concurrency-with-the-ui)).
- `DriftFocusGuardSettingsRepository` uses `guardPrivatePersistence`:
  package names are private configuration, kept out of error reports.
- `AppDatabase.open()` sets `PRAGMA busy_timeout = 3000` on Drift's
  connection (connection setting only), so a Drift write waits out the
  worker's millisecond lock instead of failing. `sqlite3` (already locked
  at 3.7.0 through drift) is named as a direct dependency for the setup
  callback's type; no new package.
- Two `DomainRule`s for budget and app-list validation messages.

## Architecture

```
Flutter (main process)                         :focus_guard process
──────────────────────                         ────────────────────
Today card / settings / picker                 FocusGuardCheckProvider
  └ FocusGuardService (domain)                   (ContentProvider, not exported)
      ├ DriftFocusGuardSettingsRepository ─┐       └ FocusGuardCheck (pure Kotlin)
      ├ TodayUsageReader                   │           ├ FocusGuardStore (SQL) ─┐
      ├ FocusGuardBackground.reconcile     │           ├ FocusGuardUsage        │
      └ AndroidFocusGuardPlatform ─┐       │           └ FocusGuardNotifier     │
             MethodChannel         │       ▼                                    ▼
FocusGuardChannel.kt ──────────────┘   app_flutter/nextrep.sqlite (Drift, schema v6)
  ├ FocusGuardUsage (access, apps, events)        ▲
  └ FocusGuardScheduler ── WorkManager ── FocusGuardWorker (main process)
                                   ContentResolver.call("check") ──┘
```

### Kotlin (`android/app/src/main/kotlin/com/nextrep/nextrep/focusguard/`)

| File | Role |
|---|---|
| `UsageEventsCalculator.kt` | pure event pairing (JVM-tested) |
| `FocusGuardUsage.kt` | AppOps Usage Access, settings intent, LauncherApps, `queryEvents` |
| `FocusGuardStore.kt` | the worker's SQL over Drift's tables: load and the atomic, forward-only claim (JVM-tested on a real SQLite) |
| `FocusGuardCheck.kt` | one background check's decisions (JVM-tested) |
| `FocusGuardDatabase.kt` | opens Drift's file safely in the `:focus_guard` process |
| `FocusGuardCheckProvider.kt` | runs the check in that process |
| `FocusGuardWorker.kt` | the WorkManager `Worker` and `FocusGuardScheduler` |
| `FocusGuardNotifier.kt` | channel, nudge, tap intent |
| `FocusGuardChannel.kt` | the MethodChannel for the UI (never opens the DB) |
| `MainActivity.kt` | registers the channel; forwards nudge taps |

No Dart isolate, Flutter engine, foreground service, exact alarm, battery
exemption, Accessibility, overlay, VPN or notification listener.

### Why a separate process for the database

Drift opens `nextrep.sqlite` through its **own bundled SQLite**
(`sqlite3` + `sqlite3_flutter_libs`). The worker reads it with Android's
framework SQLite, a second copy of the library. Two SQLite copies in one
process don't see each other's POSIX locks: one can take the other's
in-progress journal for a "hot" journal and roll it back, corrupting the
database ([sqlite.org/howtocorrupt.html](https://sqlite.org/howtocorrupt.html),
2.2.1). So the main process never opens the database natively: the worker
calls `ContentResolver.call` on a non-exported provider declared with
`android:process=":focus_guard"`, and only that process opens it. Across
processes, SQLite's ordinary file locking keeps Drift and the worker
consistent (the standard multi-process case). The provider rejects callers
with another uid and serialises its own calls.

### SQLite access (verified, not guessed)

| | |
|---|---|
| File | `AppDatabase.open()` → `driftDatabase(name: 'nextrep')` → path_provider's documents dir = `Context.getDir("flutter")` → `<dataDir>/app_flutter/nextrep.sqlite` (read from `drift_flutter` 0.3.1 and `path_provider_android` 2.3.1 sources; seen on the emulator) |
| `enabled` | INTEGER 0 / 1 |
| `daily_budget_minutes` | INTEGER 1–1440 (CHECK) |
| `last_nudged_on` | TEXT `YYYY-MM-DD` (`LocalDateConverter`) or NULL; Kotlin writes `java.time.LocalDate.toString()`, the same form |
| `updated_at`, `selected_at` | INTEGER Unix seconds (Drift's default) |
| `PRAGMA user_version` | 6; the worker does nothing on any other value |
| Journal mode | `delete` (Drift's default; seen on the emulator) |

Open flags: `OPEN_READWRITE` without `CREATE` (a missing DB is never
created), `NO_LOCALIZED_COLLATORS` (no `android_metadata` table is added;
verified absent on the emulator), and on API 28+ an explicit `DELETE`
journal mode so Android's compatibility WAL never converts Drift's file.
The configuration is read in **one** `SELECT … LEFT JOIN`, a consistent
snapshot even while the UI saves. Values Drift would never write make the
check stop (`CONFIG_UNREADABLE`), never guess.

A Dart test reads the Kotlin sources and asserts the file path, schema
version and budget limits match `AppDatabase` and `FocusGuardRules`; a
future schema change fails it until the worker is updated.

## One nudge per local day

The claim is one statement, executed **before** posting:

```sql
UPDATE focus_guard_preferences SET last_nudged_on = :today
WHERE id = 1 AND enabled = 1 AND daily_budget_minutes = :budget
  AND (last_nudged_on IS NULL OR last_nudged_on < :today
       OR last_nudged_on > :tomorrow)
  AND (SELECT COUNT(*) FROM focus_guard_selected_apps) = :count
  AND NOT EXISTS (SELECT 1 FROM focus_guard_selected_apps
                  WHERE package_name NOT IN (:measured packages))
```

Only the call that changes the row posts. It matches nothing if another
check already claimed today, Focus Guard was turned off, a restore
replaced the settings, or the budget or the app set changed since the
measurement.

Claims only move **forward**. A stale check that measured an earlier day
(just before midnight) can't replace a newer date, which would make that
newer day eligible again. A date recorded for tomorrow (a nudge before a
westward time-zone change) also counts as already nudged. Only a date more
than a day ahead, which can only come from a clock that was wrong when it
was written, is replaced, so a corrected clock never blocks Focus Guard.
The worker's early "already nudged" exit uses the same rule
(`FocusGuardStore.alreadyNudged`). Nothing ever moves a claim back: there
is no release statement, so no check, current or stale, can undo another's
claim. Only a restore clears it (below).

Order of one check (`FocusGuardCheck.run`):

1. Load settings (one snapshot). Off, no row, no apps → exit.
2. Today already claimed → exit (no measuring).
3. Usage Access → else exit. Measure local midnight → now. Usage Access
   again → else exit (the query's empty answer means nothing).
4. Below the budget (exact milliseconds) → exit.
5. Notifications off for NextRep or the `focus_guard` channel blocked →
   exit **without claiming**: the day is not used up.
6. Local date changed during the check → exit.
7. **Prepare** the notification: the notification service, the channel,
   the notification and its tap intent. If any of it fails, Android has
   never seen the notification: exit **without claiming**
   (`NUDGE_NOT_READY`), and a later check tries again.
8. **Claim**; lost → exit (`CLAIM_LOST`).
9. **Post**: only `NotificationManager.notify`. If it throws, the result is
   ambiguous (Android may already have accepted and shown it), so the
   claim is **kept** (`POST_UNCONFIRMED`) and no other nudge follows that
   day.

**At most once wins over at least once**: an ambiguous `notify` failure or
a crash between claim and post loses that day's nudge; nothing can produce
a second one. The worker always returns `success()`, so no failure becomes
a retry loop.

| Scenario | Result |
|---|---|
| below the budget / exactly / above | none / one / one |
| later checks, worker retry, repeated or overlapping checks, new process | none (stored date) |
| 12–16 concurrent checks / claims on separate connections | exactly one (JVM tests) |
| budget edited, apps edited, off → on, settings screen opened | no second nudge that day |
| next local day | eligible again |
| notifications denied | no post, day not consumed; posts once allowed |
| Usage Access revoked (before or during the query) | no post |
| preparing the notification fails (before Android sees it) | no claim; a later check nudges once |
| `notify` throws (shown or not: unknowable) | claim kept; no further nudge that day; next day eligible |
| 12 concurrent checks whose `notify` throws | exactly one `notify` call |
| restore or reconfiguration while a check measures | that check claims nothing |
| a stale check after a newer claim (restore, re-enable, another check nudged) | can't undo it; one notification |
| a check that measured yesterday, after today's claim | can't replace it |

### Concurrency with the UI

The UI's settings save used to write the whole row, `last_nudged_on`
included, from the object it loaded. A copy loaded before the worker
nudged would have erased the claim and allowed a second nudge. `save()`
is now one `INSERT … ON CONFLICT(id) DO UPDATE SET enabled, budget,
updated_at`: an existing row keeps its `last_nudged_on` whatever the
object holds (only a brand-new row takes the object's value, as there is
nothing to keep). Tested both in Dart, by running **the Kotlin claim SQL
extracted from the source** against Drift between a stale load and its
save, and on the JVM with the same upsert.

## Usage measurement

`UsageStatsManager.queryEvents`, never aggregate stats (they lag, 11A).
The window is local midnight → now, computed afresh on every read in the
device's current zone (Dart `LocalDayWindow`; Kotlin
`LocalDate.atStartOfDay(zone)`), so midnight, DST and zone changes need
nothing reset. Events are read from 6 hours before midnight so a session
that began earlier counts from midnight.

`UsageEventsCalculator`: a package's session opens on the first
`ACTIVITY_RESUMED` while none of its activities is resumed and closes when
the last one pauses or stops (split screen of one app counts once; two apps
in split screen each count); a first unmatched `ACTIVITY_PAUSED` means the
app was in the foreground before the stream; `SCREEN_NON_INTERACTIVE` and
`DEVICE_SHUTDOWN` close every session; after `DEVICE_STARTUP` dangling
sessions are dropped; an open session counts up to now; only selected
packages; each package and the total capped at the window. The UI and the
worker run the same Kotlin, so they agree for the same moment.

Nothing about usage is stored or logged. Debuggable builds log only the
check's outcome name (e.g. `BELOW_BUDGET`).

## Background work

- One **unique periodic** job `focus_guard_check`, 15 minutes, `KEEP`,
  no constraints: repeated enables, resumes and reconciliations never add
  a job or move its timing.
- `FocusGuardBackground.reconcile` runs at launch (including the relaunch
  after a restore), on every resume (Usage Access may have changed), and
  after every settings change. It schedules only while on, with apps, a
  budget and Usage Access; otherwise it cancels.
- Restore: `BackupService.restore` cancels the job right after replacing
  the data (best effort; the restored settings are off and the check
  re-reads them every run, so a stale run claims nothing).
- Reboot: WorkManager's own rescheduling (`RECEIVE_BOOT_COMPLETED`, already
  declared); no boot receiver of ours.
- Force-stop: Android removes the job until NextRep is opened again; the
  settings copy says so. NextRep doesn't work around it.
- Android may defer runs well beyond 15 minutes (Doze, standby buckets,
  job batching). The copy promises "usually around 15 minutes apart" only.

## Notification

Channel `focus_guard` ("Focus Guard", default importance), created by the
worker before posting. Title "Focus Guard"; body "You've reached today's
60-minute Focus Guard budget. Time to come back to your Arc?" with the
configured budget. No app names, amounts or anything personal. Small icon
`ic_stat_reminder` (kept by `res/raw/keep.xml`). Posted with tag
`focus_guard`, id 1, so it can never collide with the reminder plugin's
untagged ids (100–113, 200–213, 300–364).

Tap: an explicit `PendingIntent` to `MainActivity` with action
`com.nextrep.nextrep.action.FOCUS_GUARD_NUDGE` (immutable). Running app:
`onNewIntent` → channel → the existing reminder tap stream with payload
`focus_guard`. Cold start: `main.dart` asks `takeLaunchNudgeTap` once
(the intent's action is then cleared; a relaunch from Recents is
ignored). `AppRoutes.forReminder` sends `focus_guard` to Today, or home
without an active Arc. Existing payloads `today`, `journal`, `hydration`
are unchanged. No permission was added for this.

Focus Guard is not in the reminder planner: the 14 + 14 + 7 × 5 = **63**
pending maximum and its test are unchanged.

## UI

- **Entry points**: the Today card (with an active Arc); a Focus Guard
  button next to Data & Backup in Arc History (reachable from a completed
  Arc's summary); and, on onboarding, "Focus Guard is on" while it is on
  (e.g. after deleting the last Arc). Focus Guard is app-level and can stay
  on after an Arc ends, so it must always be possible to turn it off inside
  NextRep (found in review). Hidden on iOS.
- **Settings** (`/settings/focus-guard`, any app state): "FOCUS GUARD",
  "Stay aware of time spent in selected apps.", "Focus Guard sends a gentle
  reminder when your selected apps reach their combined daily budget.",
  "It does not block apps."; the switch (enabled only with Usage Access and
  at least one app; always allows off), Usage Access status and its grant
  or manage action, notification status (separate, explained), the apps
  (live labels; "Not installed" for removed ones), the combined budget
  (presets 15 min – 4 h, or 1–1440 minutes typed), and how background
  checks work, including force-stop. Re-read on resume.
- Turning on asks for notification permission only if NextRep doesn't
  have it (the user's tap, as for reminders). Denied: it turns on anyway,
  measures, and says it can't send its reminder. Turning off cancels the
  job and keeps apps, budget and the day's nudge record.
- **Picker** (`/settings/focus-guard/apps`): launcher apps only, searchable,
  multi-select, nothing pre-selected, "N chosen · up to 100" (unchecked
  rows disabled at 100), "No longer installed" section for removal, empty
  and error states. Saves package names only.
- **Today card**, under the habits: off → "Stay aware of time spent in
  selected apps."; on without apps → "Choose the apps to keep an eye on.";
  Usage Access off → says so (never "0 min"); read failed → says so; else
  `38 / 60 min`, a bar, `22 min remaining`, and **Shield strong** (< 80 %),
  **Near today's limit** (≥ 80 %), **Budget reached** ("Budget reached.
  Tomorrow is a fresh day."). Minutes used round down and remaining round
  up; the state uses exact durations. Re-read on appearing, resume, local
  midnight and settings changes; never polled. Omitted on iOS.
- Copy never says failed, broken, wasted or lost; nothing touches habits,
  `DayRules`, XP, levels, achievements, streaks, Perfect Day or Minimum Day
  (a test compares every Arc row before and after crossing the budget).

## Privacy

- Off by default; only the user turns it on, picks apps and grants Usage
  Access (system page, user's tap only).
- Stored: on/off, package names, budget, the date of the last nudge. Not
  stored: usage amounts, per-app or per-day usage, launches, labels, icons.
- Nothing is sent anywhere; still no `INTERNET`.
- Backups (format 3) contain the budget and package names, never the
  enabled state, the nudge date or usage. PRIVACY.md now says exported
  backups may contain package names and are not encrypted, and that a
  restore leaves Focus Guard off.
- Share cards and captions are built from `DaySummary`, which has no
  Focus Guard data (tested on the Today's Progress preview).
- Tests and this record use synthetic package names (`org.example.*`)
  only; no device's app inventory is committed.

## Permissions

| | Release APK (`aapt2 dump permissions`) |
|---|---|
| v1.1.0 set, kept | `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| Added | `PACKAGE_USAGE_STATS`, `WAKE_LOCK` |
| Absent | `INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`, `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, storage, media, contacts, accounts, camera, microphone |

Merged components (`aapt2 dump xmltree`): `SystemForegroundService`
removed (`tools:node="remove"`, with WorkManager's `FOREGROUND_SERVICE` and
`ACCESS_NETWORK_STATE`, as qualified in 11A); WorkManager's
`SystemJobService` (`BIND_JOB_SERVICE`), `SystemAlarmService`, its
receivers (constraint proxies disabled; `DiagnosticsReceiver` guarded by
`DUMP`) and `InitializationProvider` kept; `FocusGuardCheckProvider`
`exported=false`, `process=":focus_guard"`; the launcher
`<queries>` intent. No Accessibility, VPN or notification-listener
service, no foreground service.

Audits: `.github/workflows/flutter-ci.yml` and
`tool/release/prepare_android_release.sh` no longer forbid
`PACKAGE_USAGE_STATS`; both now require the **exact** permission set above
(anything else fails), keep the forbidden list (adding
`ACCESS_NETWORK_STATE`), fail on Accessibility, VPN or notification-listener
binds and on any foreground service, and check Focus Guard's provider is
present and not exported. The release script's logic was run against the
built APK (pass) and against a tampered expectation and a tampered
provider check (both fail). Its signing, staging and checksum steps are
unchanged.

## Signing safety

The main checkout has `android/key.properties`, so a release build there
would be signed with the permanent key. All Phase 11C work and builds ran
in a separate worktree without it: every release APK built here is
debug-signed and is a compile and audit artifact only. The signing key was
not read, used or changed. Device qualification used an isolated
`com.nextrep.nextrep.qualification` package (a temporary, uncommitted
`applicationIdSuffix`), never the production id.

## R8 finding (release builds)

Qualifying the **minified** build found a crash the debug build and CI
could not: every release process died at startup in
`androidx.startup.InitializationProvider` with `NoSuchMethodException:
androidx.work.impl.WorkDatabase_Impl.<init>`. WorkManager 2.10.1 brings
Room 2.6.1, whose consumer rule `-keep class * extends
androidx.room.RoomDatabase` keeps the class but, under R8's full mode
(AGP's default), not the no-argument constructor Room calls by
reflection. Fixed with `android/app/proguard-rules.pro` (picked up by
Flutter's Gradle plugin): `-keep class * extends androidx.room.RoomDatabase
{ <init>(); }`. The fixed minified build was re-qualified on the emulator
(launch, measurement, nudge, cold-start tap; 0 fatal exceptions). CI and
the release script now also fail if the release dex
(`apkanalyzer dex packages`) lacks `WorkDatabase_Impl.<init>()`, the
worker's or the provider's constructor, because CI builds the release APK
but never runs it.

## Automated tests

Flutter 3.47.5 / Dart 3.13.4, Android build-tools 36.0.0, Xcode 27.

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (278 files, 0 changed) |
| `flutter analyze` | no issues |
| Migration tests (v1 → v6, CI set) | 52 / 52 |
| Backup format tests (1, 2, 3, CI set) | 90 / 90 |
| Release qualification tests | 39 / 39 |
| Focus Guard tests (CI set: 11A foundation + new) | 104 / 104 |
| Hydration and reminder tests (incl. the ≤ 63 pending test) | 82 / 82 |
| `flutter test` | **976 / 976** (902 before + 74) |
| Native JVM tests (`./gradlew :app:testDebugUnitTest`) | **67 / 67**: event calculation 23, store SQL on a real SQLite 14, check 30 |
| `flutter build apk --debug` / `--release` | PASS / PASS (64.8 MB, `com.nextrep.nextrep` 1.1.0 (2), debug-signed) |
| Release permission and component audit (script logic on the APK) | PASS; negative checks fail as intended |
| `flutter build ios --simulator` / `--release --no-codesign` | PASS / PASS (21.7 MB) |

New Dart tests: `test/domain/focus_guard_service_test.dart` (configuration,
permissions, picker, usage, background work, the meter's thresholds),
`test/data/focus_guard_persistence_test.dart` (the Kotlin contract, the
Kotlin claim SQL against Drift, the stale-save interleaving, real restores
of formats 1, 2 and 3 with the job cancelled and nothing left to claim),
`test/features/phase11c_focus_guard_flow_test.dart` (unsupported platform,
settings, grant action only on tap, picker search and removal of an
uninstalled app, budget validation, enable / deny / disable, revocation,
every card state, midnight, 2× text and labels, unchanged Arc rows, share
card, taps while running, cold start and without an Arc, entry points
without an Arc, restore at launch) and routing cases in
`test/app/app_routes_test.dart`. Native: `android/app/src/test/…/focusguard/`
(synthetic `org.example.*` packages, SQL run against Drift's captured DDL,
16 concurrent claims → exactly one; prepare failures, ambiguous `notify` failures, stale checks after restore and reconfiguration).

## Android API 36 emulator qualification

`sdk_gphone64_arm64`, Android 16 (API 36), the AVD that holds the
**official signed v1.1.0** (first installed 2026-10-12 22:38:38, updated
22:39:16). It was never touched: the qualification ran on a separate
`com.nextrep.nextrep.qualification` package (debug build, then the
minified release-type build, both debug-signed), uninstalled afterwards.
Test apps: two stock system apps (Settings and Clock). Background runs were
either the real periodic schedule or the real job force-run with
`cmd jobscheduler run -f -n androidx.work.systemjobscheduler` after moving
the clock past the period (WorkManager itself refuses an early forced run
of periodic work: "Delaying execution … before schedule"). No test receiver
or debug control exists in any build.

| # | Step | Result |
|---|---|---|
| 1 | New install, Arc started | Focus Guard **off**; Today shows the set-up card; no job; no prompt |
| 2 | Open settings | "Not allowed"; switch disabled with its explanation |
| 3 | Tap "Allow Usage Access" | `Settings$AppUsageAccessSettingsActivity`, NextRep's own page |
| 4–5 | Grant with the real switch, go back | `GET_USAGE_STATS: allow`; "Allowed" without a restart |
| 6–7 | App picker | 18 apps = 20 launcher packages minus both NextRep installs; search works; `QUERY_ALL_PACKAGES` absent |
| 8 | Choose two apps, save | `focus_guard_selected_apps` holds both, in order, in Drift's real `app_flutter/nextrep.sqlite` (user_version 6, journal `delete`, no `android_metadata`) |
| 9 | Budget 1 min | stored 1; still off |
| 10 | Turn on, **deny** the Android 16 prompt | on, "measure but can't send its reminder"; one job `focus_guard_check` (15 min, `FocusGuardWorker`) |
| 11–13 | ~75 s in a chosen app, back to Today | card from "0 of 1" to "1 / 1 min, Budget reached. Tomorrow is a fresh day." |
| 14a | **Natural** periodic run, 22:55, notifications denied | `NOTIFICATIONS_OFF`; `last_nudged_on` NULL; nothing posted |
| 14b | Notifications allowed, next period | `NUDGED`; `last_nudged_on = 2026-10-14` |
| 15 | The notification | channel `focus_guard`, tag `focus_guard`, id 1, category reminder, "You've reached today's 1-minute Focus Guard budget. Time to come back to your Arc?" |
| 16 | Tap it, app in the background on the settings screen | NextRep on **Today**; notification cleared |
| 17 | Next period | `ALREADY_NUDGED`; still one notification, same post time |
| 21 | Turn off; turn on again | 0 jobs, apps and nudge date kept; 1 job, its first run `ALREADY_NUDGED`, no notification |
| 22 | Reboot, NextRep not opened | job back in JobScheduler (WorkManager's own rescheduling) |
| 23 | `am kill`, next period | ran in a new process (and the `:focus_guard` process): `ALREADY_NUDGED` |
| 24 | `am force-stop` | job removed, package `stopped=true`; opening NextRep → job back, `stopped=false` |
| 25 | Next local day (00:05) | — |
| 19 | Revoke Usage Access with the real switch, leave by Home | worker `NO_USAGE_ACCESS` (no-op) |
| 18 | Back to NextRep | "On, but paused: Usage Access is off."; card "Usage Access is off, so today's time can't be measured" (no "0 min"); job cancelled on resume |
| 20 | Re-grant from the card's path | "On. Checking in the background."; job back (first run `BELOW_BUDGET`); card "0 of 1" for the new day |
| 25 | ~75 s in a chosen app, next period | `NUDGED` again; `last_nudged_on = 2026-10-15` |
| — | Process killed, tap the nudge | cold start on **Today** |
| R8 | Minified build installed in place | launch, measurement, one job, `NUDGED` notification, cold-start tap to Today; 0 fatal exceptions (after the R8 fix above) |
| 26 | Release permissions | see [Permissions](#permissions) |

Afterwards the qualification package was uninstalled (no job left),
automatic time restored, and the official v1.1.0 verified unchanged
(versionName 1.1.0, same install and update times, same signer).

Notes:

- Android 16 added a `FLEXIBILITY` constraint to the job; the natural run
  came about 17 minutes after enabling.
- Moving the wall clock by hand makes Android's UsageStatsService shift its
  stored event times by the same amount, so a day-long jump can carry
  earlier usage into "today" (seen once: "4 of 1" before any use on the
  jumped-to day). A real midnight or a time-zone change doesn't change
  epoch time and doesn't do this. A test artifact, not a product issue.
- A wall-clock jump while NextRep is in the foreground isn't noticed until
  the next resume (the midnight ticker runs on monotonic time); a real
  midnight is. This is the app's existing behaviour, shared with Today.

## Physical device

**Deferred, not run.** The OnePlus CPH2707 was not connected to this
machine during Phase 11C (`adb devices` listed only the emulator), so no
physical qualification was attempted and the owner's official v1.1.0 was
not at risk. Phase 11A's physical evidence of the same Android APIs stands;
the signed v1.1.0 → v1.2.0 physical upgrade belongs to Phase 11F.

## iOS

`flutter build ios --simulator` and `flutter build ios --release
--no-codesign` pass (no `ios/` change, no entitlement, no permission
prompt). The simulator build was installed and cold-launched on an iPhone
17 simulator: onboarding, no crash; Focus Guard is omitted (unsupported
platform: no card, no entry, reconcile only calls the disabled scheduler).

## Known limitations and review decisions

- **Best effort**: Android may run the check much later than 15 minutes
  (Doze, standby buckets, job batching, Android 16 flexibility), so the
  nudge can be late; after a force-stop nothing runs until NextRep is
  opened. The copy promises neither real time nor exact timing.
- **Restore exception (by design).** The format-3 restore contract is
  kept: Focus Guard **off**, `last_nudged_on = NULL`, selected apps and
  budget preserved. Nothing can nudge after a restore until the user turns
  Focus Guard on again. The one narrow exception to "at most one nudge per
  local day": **a user who explicitly re-enables Focus Guard after a full
  restore may receive a new nudge on that local day**, even if one was sent
  before the restore. Tested (`focus_guard_persistence_test.dart`). No
  schema or backup change.
- SQLite's busy handler doesn't cover one lock pattern: a Drift
  transaction that read first and then writes, at the exact moment the
  worker's one-row claim holds its write lock (milliseconds, at most once
  or twice a day), fails with "database is locked" and is reported like
  any storage error. `save()` writes first and isn't affected.
- Usage is Android's event accounting: accurate to seconds in practice,
  not guaranteed to the second; picture-in-picture and split screen may
  count as foreground; two instances of one activity class count as one.
- Android only. Physical qualification deferred (above).

## Out of scope (unchanged)

No About screen, update check, `INTERNET`, APK download or install, schema
v7, backup format 4, version bump, tag or release, Focus Guard XP or
achievements, app blocking, usage history or iOS Screen Time. Phase 11D
(About + manual update check), 11E (integration and polish) and 11F (v1.2
release qualification, `1.2.0+3`, tag, publication) remain.
