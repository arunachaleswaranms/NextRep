# Phase 11B: Smart Hydration and the v1.2 Persistence Foundation

## Objective

Implement **Smart Hydration** (Hydration Coach) end to end, and introduce
the **one** database and backup version of v1.2 now, so Phase 11C needs no
further migration:

- Hydration Coach: preferences, a pure deterministic planner,
  progress-aware notification reconciliation, Minimum Day and habit
  revision integration, Reminders UI.
- **Schema v6** (v5 → v6) and **backup format 3** (write 3, read 1 + 2 + 3).
- Focus Guard's persistence tables and backup shape **only**. No Focus
  Guard product behaviour, screen, permission, worker or notification.

Version stays **1.1.0+2**. Nothing was tagged or published.

## Baseline

| | |
|---|---|
| `main` | `184661100dff7e6134716f87314c52ec6243f42c` (PR #15, Phase 11A, merged), clean tree |
| Post-merge CI | run 38425483613, both jobs success |
| Focus Guard feasibility | **GO** (Phase 11A) |
| Version | `1.1.0+2` |
| Database schema | v5 |
| Backup | write 2 / read 1 + 2 |
| `flutter test` | 800 / 800 |

## Smart Hydration contract

- **Optional, off by default.** Turning it on is a user action and the
  only moment notification permission may be requested.
- **Only the built-in Water habit**, recognised by its stable id `water`
  (`builtInWaterHabitId`), never by title. A renamed built-in Water habit
  ("Morning Hydration") still counts; a custom habit titled "Water",
  "Water Intake" or "Drink Water" (id `custom_<hex>`) never does.
- **No separate goal.** Hydration Coach paces against the Arc's own Water
  target for each date: baseline, habit revisions, enabled state and, for
  today, the Minimum Day target. Settings hold no target.
- If the active Arc has no built-in Water habit, the settings say
  "Hydration Coach works with the built-in Water habit in your active
  Arc." and the switch can't be turned on (only off). Water is never added
  to an Arc.
- No XP, no achievement, no medical claim, no computed "water
  requirement". The existing **Hydration Rhythm** achievement still derives
  from Water history only; logging Water earns the ordinary habit XP only.
- Share cards are unchanged: they are built from the day's read model
  (`DaySummary`), which holds no reminder or hydration setting, so the
  window, mode, notification state and checkpoint times can never appear
  on a card.

## Modes

| Mode | Nudges a day, at most | Stored name |
|---|---|---|
| Gentle | 3 | `gentle` |
| **Balanced** (default) | 4 | `balanced` |
| Supportive | 5 | `supportive` |

These are **maximums**: on pace, ahead or done means no nudge. Stored
names are part of schema v6 (a CHECK constraint) and backup format 3 and
must never be renamed.

## Active window

- Default **08:00 – 20:00**.
- Same local day only: start before end, **8 to 18 hours** long. No
  overnight window (e.g. 22:00 → 06:00) in v1.2.
- Enforced in the domain (`HydrationWindow`: the constructor throws
  `DomainRule.invalidHydrationWindow`; only `tryCreate` returns null), in
  the database (CHECK on the window length), and by the backup codec. The
  UI validates both picks together; an invalid pair saves nothing and
  explains the rule.

## Checkpoint algorithm (`HydrationPlanner`)

For a date with Water target `T` (effective for that date) and mode
maximum `M`:

1. `N = min(M, T)` checkpoints, so each one asks for at least one more
   glass and no two expect the same amount.
2. Base times: for `N ≥ 2`, evenly from **15 %** to **90 %** of the window
   (08:00 – 20:00, Balanced: 09:48, 12:48, 15:48, 18:48). For `N = 1`,
   **62.5 %** (15:30), past the middle of the day.
3. Checkpoint `i` expects `ceil(T × (i + 1) / N)` cumulative glasses; the
   last expects `T`. Target 8 / Balanced: 2, 4, 6, 8. Target 3 /
   Balanced: 1, 2, 3. Target 8 / Supportive: 2, 4, 5, 7, 8.
4. A checkpoint becomes a notification only if, when the plan is made:
   - it is still ahead (`at > now`; a passed checkpoint is never
     recreated),
   - the day's Water is below its expectation (**progress-aware
     suppression**: 5 logged against an expectation of 4 → no nudge),
   - it isn't within the **45-minute recent-log grace** of the last Water
     log today (skipped, not moved; later checkpoints stay).
5. A complete target removes every remaining nudge for that day.

Future dates are planned from no progress with their own effective
configuration; Minimum Days are never invented for them. Dates outside
participation (before a seasonal Arc was joined, after its end, or with
no active Arc) get nothing; this reuses `WinterArcSession.isParticipatingOn`
and `positionOn`.

**Order and spacing hold by construction.** The tightest case (8-hour
window, 5 checkpoints) has bases 90 minutes apart, so after ±15 minutes
they are still at least an hour apart; the first base is ≥ 72 minutes after
the start and the last ≥ 48 minutes before the end, so every time stays
inside the window. A test sweeps every valid window on a 45-minute grid ×
3 modes × 7 targets × 40 dates (> 100,000 checkpoints) for order, ≥ 60
minutes spacing, containment and strictly increasing expectations.

## Deterministic humanisation

Each checkpoint moves by `-15..+15` minutes:

```
jitter = fnv1a32("YYYY-MM-DD|mode|HH:MM|HH:MM|index") mod 31 − 15
```

`stableHash` is the published **32-bit FNV-1a** over UTF-8 bytes (tested
against its reference vectors), not `String.hashCode`, `Object.hash` or
`Random`. The same date, mode, window and index always give the same time,
in any process or app version, so a resume, restart or re-plan never moves
a pending nudge; a different date usually gives different times; a mode
or window change gives a new, equally stable schedule.

## Effective target authority

The reminder service gathers, for each of the 7 days, a `HydrationDay` from
the Arc's stored records: `DayRules.recordFor(date, habits, mode,
progress).entryFor('water')`. That is the same authority Today, XP and
achievements use, so Hydration Coach has no Minimum Day or revision logic
of its own. The planner receives the participation flag, the entry
(effective target, normal and minimum configuration, progress) and the
last Water log time, plus `now`; it never reads storage.

The "last log" is the `updated_at` of today's Water progress row, which is
also refreshed when a Minimum Day change re-settles Water's completion.
That only ever skips a checkpoint in the 45 minutes after the change.

### Minimum Day

| Step | Water today | Effective target | Remaining nudges today |
|---|---|---|---|
| Normal day, 3 logged | 3 | 8 | the 4-, 6- and 8-glass checkpoints |
| Activate Minimum Day (minimum 3) | 3 | 3 | **0** (complete) |
| Undo / Return to full targets | 3 | 8 | the same checkpoints return |

No progress is discarded (`DayRules` keeps values; tested through the real
services and Drift).

### Habit revisions

- A Water goal change is stored from the next challenge day; today keeps
  its plan and later days use the new target from that date.
- Water disabled by a revision: no hydration on those dates; re-enabled
  later: planning resumes from the re-enable date.
- Past dates are never planned.

## Reconciliation

There is still **one** reconciliation (`ReminderService.reconcile`) that
builds the complete desired set, daily + reflection + hydration, and hands
it to the scheduler. There is no second scheduler: pending notifications
are only ever cleared wholesale by that reconciliation (an empty plan, or
the first schedule of a process) and by a restore.

It runs on: app launch; app resume; local day rollover (`DayChangeTicker`);
active Arc change, Arc start and Arc close (`arcResolutionProvider`);
reminder, mode and window changes (`ReminderService.update`); **every
persisted change to the active Arc** (`arcRefreshProvider`, bumped after
Water increment / decrement, Minimum Day on / off, and habit edits,
including Water target and enabled revisions); and restore completion (the
app restarts on the restored data).

**Scheduler diffing.** Logging a glass re-plans everything, so the
plugin-backed scheduler no longer cancels and recreates all pending
notifications after the first schedule of a process: `ReminderChanges`
compares the plan with what the OS reports as pending (and what this
process scheduled) and cancels only ids that left the plan and schedules
only new or changed reminders. Notifications already shown are never
removed. Daily and reflection reminders are left untouched by a Water log.

## Notifications

| | Daily | Evening reflection | Hydration |
|---|---|---|---|
| Horizon | 14 days | 14 days | **7 days** |
| Ids | 100 + day | 200 + day | **300 + 10 × day + slot** (300–364) |
| Payload | `today` | `journal` | **`hydration`** → Today |
| Android channel | `daily_reminder` | `reflection_reminder` | **`hydration_coach`** ("Hydration Coach") |
| Title / body | unchanged | unchanged | "Hydration check" / "A little water now can keep you on pace." |

- **Maximum pending: 14 + 14 + 7 × 5 = 63**, within iOS's 64
  (`ReminderPlanner.maxPending`, tested in the worst configuration:
  everything on, Supportive, Water ≥ 5, full horizon). Hydration is
  deliberately not on the 14-day horizon (that would be 98). If the app
  isn't opened for more than 7 days, hydration nudges pause until the next
  reconciliation.
- Ids are deterministic, never stored, and can't collide across kinds,
  dates or slots.
- Copy never shows amounts, targets, habit titles, Journal data, XP,
  moods or bedtime, and makes no medical claim.
- `AppRoutes.forReminder`: `hydration` opens Today of the active Arc; a
  stale one (Arc completed, new setup) falls back to home like the others;
  unknown payloads still open Today. Existing payload meanings unchanged.
- `AndroidScheduleMode.inexactAllowWhileIdle`, `reminder` category, no
  exact alarm, no foreground service.

### Permission

Unchanged model: asked only when the user turns Hydration Coach on, never
at startup. Denied: nothing is saved (the switch stays off), nothing is
scheduled, the app explains, and the style and active hours stay editable.
Revoked later in system settings: the existing "notifications are turned
off" notice covers Hydration Coach too.

## Schema v6

`drift_schemas/drift_schema_v6.json`, `schema_versions.dart` step and
`test/generated_migrations/schema_v6.dart` were generated with drift_dev;
v1–v5 snapshots are unchanged.

`reminder_preferences` gains (appended, with defaults for the existing
row):

| Column | Type / default | Constraint |
|---|---|---|
| `hydration_enabled` | bool, `0` | |
| `hydration_start_hour` / `_minute` | int, `8` / `0` | 0–23 / 0–59 |
| `hydration_end_hour` / `_minute` | int, `20` / `0` | 0–23 / 0–59, and window length 480–1080 minutes |
| `hydration_mode` | text, `balanced` | `IN ('gentle', 'balanced', 'supportive')` |

Focus Guard tables, created now so v1.2 has one migration:

| Table | Columns | Constraints |
|---|---|---|
| `focus_guard_preferences` | `id`, `enabled`, `daily_budget_minutes`, `last_nudged_on` (date, nullable), `updated_at` | `id = 1` singleton; budget 1–1440 |
| `focus_guard_selected_apps` | `package_name` (PK), `sort_order`, `selected_at` | name length 3–255; `sort_order ≥ 0`, unique |

No usage-duration column, no daily history, no per-app usage, no XP and no
Arc foreign key: app-level settings only.

### v5 → v6 migration

Additive only: six `ADD COLUMN`s (the end-minute CHECK reads the other
window columns, so it is added last) and two `CREATE TABLE`s. No row is
rewritten.

Tested (`test/data/migration_v6_test.dart`) with a realistic synthetic
v1.1 database: a completed rolling Arc and an active Seasonal Arc joined
late, habit revisions (one pending), Minimum Days (one today), progress,
XP (habit and Perfect Day), achievements, a reflection and saved reminder
preferences. Every v5 row and value is unchanged; the reminder row gains
Hydration Coach off, 08:00 – 20:00, Balanced; the Focus Guard tables are
empty and read as defaults; both Arcs, history, XP, achievements and the
Journal read as before; Hydration Coach then works with the migrated
active Arc's **renamed** built-in Water habit, today's Minimum Day target
and tomorrow's pending revision. Empty v1, v2, v3, v4 and v5 databases
upgrade to exactly v6; the data-carrying v1 → … → v5 suites now migrate
through to v6.

## Backup format 3

Writes **3**, reads **1, 2 and 3**. Arcs are laid out as in format 2.

```json
"data": {
  "arcs": [...],
  "reminders": {
    "dailyTime": "07:15", "reflectionTime": "22:30",
    "hydrationStart": "06:30", "hydrationEnd": "21:00",
    "hydrationMode": "gentle"
  } | null,
  "focusGuard": {
    "dailyBudgetMinutes": 45,
    "selectedApps": ["<package name>", ...]
  } | null
}
```

- **Restore-off safety:** after any restore the daily reminder, the
  evening reflection and **Hydration Coach are off**; pending
  notifications are cancelled; nothing is scheduled and no permission is
  requested. Hydration window and mode are kept.
- **Focus Guard restore contract:** budget and selected package names are
  restored in order; `enabled = false` and `last_nudged_on = null` always.
  A backup never contains Focus Guard's enabled state, its last nudge,
  today's measured usage or any usage history. Nothing in the app reads
  these settings until Phase 11C.
- Formats 1 and 2 are frozen: they may not carry hydration fields or
  `focusGuard`, and restore with Hydration Coach at its defaults and no
  Focus Guard settings. A format-2 body relabelled 3 is rejected (missing
  format-3 fields), not silently read.
- Validation: window rules, known mode, budget 1–1440, at most 100
  selected apps, each a well-formed package name, no duplicates; unknown
  fields rejected.

### Compatibility

| File → app | Result |
|---|---|
| format 1 (Phase 5 fixture) → v1.2 code | **PASS** |
| format 2 (genuine v1.1 export, new fixture `test/fixtures/v1_1_backup_v2.nextrep`, written by `main` at `1846611`) → v1.2 code | **PASS** |
| format 3 → v1.2 code | **PASS** (round trip identical) |
| format 3 → v1.1 code | **unsupported, as expected**: verified by running `main`'s decoder on a format-3 export: `BackupProblem.unsupportedVersion`, "That backup was made by a newer version of NextRep. Update the app to restore it. Nothing was changed." |

### Privacy of format 3 (technical note)

Once Focus Guard ships (Phase 11C), a backup from a user who selected
apps will contain those apps' **package identifiers**, which reveal which
apps the user wanted to limit. Backups remain local files the user
creates and stores, **not encrypted by NextRep**. User-facing PRIVACY.md
wording for this is deferred to Phase 11C, when the feature becomes
available; no Focus Guard is advertised now. Every package name in tests
is synthetic (`org.example.*`); no real app list is committed.

## Version and permissions

- `pubspec.yaml` version **1.1.0+2**, unchanged (release APK: versionName
  1.1.0, versionCode 2).
- Release permissions, unchanged from v1.1.0: `RECEIVE_BOOT_COMPLETED`,
  `VIBRATE`, `POST_NOTIFICATIONS`, app-private
  `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- The release `AndroidManifest.xml` (`aapt2 dump xmltree`) is **identical**
  to a release build of `main` (`1846611`).
- Absent: `INTERNET`, `PACKAGE_USAGE_STATS`, `QUERY_ALL_PACKAGES`,
  `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, exact alarms, storage,
  media, contacts, accounts, camera, microphone, `FOREGROUND_SERVICE`,
  `WAKE_LOCK`; no Accessibility or VPN service.
- The CI audit and `tool/release/prepare_android_release.sh` were
  **tightened**, not relaxed: they now also fail on `QUERY_ALL_PACKAGES`,
  `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES` and
  `FOREGROUND_SERVICE`, and CI fails on any service guarded by
  `BIND_ACCESSIBILITY_SERVICE` or `BIND_VPN_SERVICE`. `PACKAGE_USAGE_STATS`
  and `INTERNET` stay forbidden.

## Automated validation

Flutter 3.47.5 / Dart 3.13.4, JDK 21, build-tools 36.0.0, Xcode 27.

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (267 files, 0 changed) |
| `flutter analyze` | no issues |
| Migration tests (v1 → v6, CI set) | 52 / 52 |
| Backup format tests (formats 1, 2, 3, CI set) | 90 / 90 |
| Release qualification tests | 39 / 39 |
| New: hydration planner / service / flow | 40 / 18 / 11 |
| New: migration v6 / backup format 3 | 14 / 16 |
| `flutter test` | **902 / 902** (800 before) |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS (64.2 MB, `com.nextrep.nextrep` 1.1.0 (2)) |
| Release permission audit | PASS (exact v1.1.0 set) |
| `flutter build ios --simulator` | PASS |
| `flutter build ios --release --no-codesign` | PASS (21.5 MB) |

Coverage of the hydration matrix: off → none; no active Arc; no built-in
Water; custom "Water" ignored; renamed built-in Water works; Water
disabled; target complete; ahead suppressed; behind eligible; 45-minute
grace; decrement brings checkpoints back; Minimum Day on and undone;
target revision; disabled and re-enabled revisions; Gentle / Balanced /
Supportive; targets 1, 2, 3, 8, 12, 13; window validation (8 h / 18 h
bounds, overnight, empty); deterministic jitter; local midnight rollover
and local-date semantics; seasonal participation and Arc end; payload →
Today; permission denied; restore → off; ≤ 63 pending; daily and
reflection plans byte-for-byte unchanged with hydration on.

UI (widget) coverage: section visible and off by default; enable with
permission; denial; mode selection; window editing (valid, overnight,
too short, cancelled); no-built-in-Water explanation (with a custom
"Water" habit); renamed Water recognised; settings survive a restart;
restore keeps settings and turns it off; Water logged on Today re-plans
immediately both ways; hydration tap opens Today; 2× text and reduced
motion. No animation was added.

## Runtime qualification

### Android: API 36 emulator (`sdk_gphone64_arm64`, Android 16)

The emulator held the **official signed v1.1.0** (`63,684,809` bytes, the
v1.1.0 signer `65b70cd0…f0ba`, an Arc in setup). An emulator snapshot was
saved first; the Phase 11B release build (same signer, still 1.1.0 (2))
was installed over it with `adb install -r`.

| Step | Result |
|---|---|
| In-place update v1.1.0 → Phase 11B | `Success`; `firstInstallTime` unchanged (2026-10-12 22:38:38); the setup and its habits intact after the live **v5 → v6 migration** |
| Start the Arc; open Reminders | Hydration Coach section below the existing reminders; off; Balanced; 8:00 AM – 8:00 PM; no times or cadence shown |
| Turn on, **deny** the real Android 16 prompt | "Notifications weren't allowed, so the reminder stays off…"; switch off; **0** NextRep alarms |
| Active hours 2:00 PM – 11:59 PM (set while off) | saved |
| Active hours 10:00 PM → 6:00 AM | rejected with the window rule; previous window kept |
| Turn on, **allow** | **25** pending alarms: today 22:54 (the one checkpoint left) + 6 days × 4, at exactly the planner's deterministic times (e.g. 14 Oct 15:43, 17:57, 20:42, 22:56); `RTC_WAKEUP` via `ScheduledNotificationReceiver` with inexact windows; no exact alarm |
| Real delivery | posted at **22:54:16**: id 303, channel `hydration_coach` ("Hydration Coach"), category reminder, "Hydration check" / "A little water now can keep you on pace." |
| Tap it in the shade | NextRep opened on **Today** (Day 1) |
| Clock moved to 14 Oct 15:00 (`cmd alarm set-time`), resume | Day 2; re-planned to **28** (7 days × 4, the horizon moved) |
| Log 1 glass at 15:00 | 15:43 checkpoint **skipped** (45-minute grace): 17:57, 20:42, 22:56 left (27) |
| 5 glasses | 17:57 (expects 4) suppressed: 20:42, 22:56 (26) |
| Minimum Day (5 of 3) | today **0** (24) |
| Undo | 20:42, 22:56 back (26); Water still 5 / 8 |
| 8 of 8 | today **0** (24) |
| Decrease to 7 | 22:56 back (25); 20:42 had already been met |
| Logcat | no Flutter errors or exceptions |

Afterwards automatic time was restored and the emulator snapshot reloaded,
so the emulator is again on the official v1.1.0 with its original data
(for Phase 11F's real migration run).

### Physical devices

**Not tested on a physical device in Phase 11B.** The owner's OnePlus
(production v1.1.0) was connected over wireless adb during the session
and was deliberately **not touched**: every command targeted
`emulator-5554` only. The real v1.1.0 → v1.2.0 phone migration belongs to
Phase 11F.

### iOS

`flutter build ios --simulator` and `flutter build ios --release
--no-codesign` pass. The simulator build was installed and cold-launched
on an iPhone 17 simulator (fresh database created at schema v6, onboarding
shown, no crash). No simulator UI automation was available, so Hydration
Coach on iOS is covered by the platform-neutral domain, service and widget
tests; it uses only the existing local-notification permission. No
physical iPhone (not required); VoiceOver and TalkBack remain non-blocking.

## Deferred

- **Phase 11C**: Focus Guard product: Usage Access, app picker,
  WorkManager worker, Today card, threshold notification, platform
  channel, `PACKAGE_USAGE_STATS` / `WAKE_LOCK` / launcher `<queries>`,
  and its PRIVACY.md wording (including package names in backups).
- **Phase 11D**: About screen and manual update check; `INTERNET`.
- **Phase 11E / 11F**: integration polish; the `1.2.0+3` version bump,
  real v1.1.0 → v1.2.0 migration on the owner's phone, release notes, tag
  and publication.
