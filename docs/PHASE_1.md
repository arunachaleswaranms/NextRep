# Phase 1 — Foundation and Day 1 vertical slice

## Objectives

Phase 1 builds a production-oriented Flutter foundation and proves one real
end-to-end flow:

```
Onboarding → Habit Setup → Start Winter Arc → Today → complete a habit
→ progress persists locally → app killed/relaunched → state still there
```

Correctness, deterministic domain logic, persistence and tests take priority
over visual polish.

## Architecture decisions

| Decision | Choice | Why |
|---|---|---|
| Layering | `domain/` (pure Dart) ← `data/` (Drift) ← `features/` (UI) | Business rules are testable without Flutter or SQLite. Storage can be swapped behind interfaces. |
| Truth | `HabitProgressRules.apply` is a pure function | One authority decides progress and XP. Persistence applies its output, and the UI reflects persisted state. |
| Atomicity | `ProgressRepository.applyTransition` runs read → rule → write in one SQLite transaction | Drift runs transactions one at a time, so rapid taps can't interleave a read-modify-write. |
| Serialization | `SerialQueue` in `TodayController` and `WinterArcService` | Taps are applied in order. A double tap on "Let's Begin" or "Start" can't create two sessions. |
| Time | `Clock` interface + `LocalDate` value type | No `DateTime.now()` in logic. Day maths runs on UTC midnights, so it is immune to DST. |
| Errors | Sealed `AppFailure` (`PersistenceFailure`, `DomainFailure(rule)`, `UnexpectedFailure`) | Repositories wrap storage exceptions with the operation name. Controllers report every failure to `ErrorReporter` (local log) and return an `ActionResult`, and the UI shows a message. Nothing is swallowed. |
| State management | Riverpod 3, no code generation | A small composition root (`app/dependencies.dart`) plus feature-scoped `AsyncNotifier`s. Easy to override in tests. Automatic retry is disabled so failures surface. |
| Routing | go_router with boot-derived initial location | Scales to a `StatefulShellRoute` for future tabs (Journey, Progress, Journal, Profile). No empty placeholder screens. |

### Dependencies

| Package | Version | Reason |
|---|---|---|
| `flutter_riverpod` | ^3.4.3 | State management + dependency injection with test overrides. |
| `drift` / `drift_flutter` | ^2.35.1 / ^0.3.1 | Typed SQLite with transactions, unique/check/foreign-key constraints, a migration API and schema snapshots. Actively maintained (released Sep 2026). Original Isar has not been released since Apr 2023. Only a community fork continues it. |
| `go_router` | ^18.0.2 | Flutter-team router. Declarative routes, ready for shell/tab routes. |
| `intl` | ^0.20.3 | Date labels on Today ("Thursday, 1 October"). |
| `drift_dev`, `build_runner` (dev) | | Drift code generation and schema dumps. |
| `integration_test` (dev, SDK) | | On-device end-to-end test. |

`cupertino_icons` was removed (unused). No analytics, ads, Firebase or network
packages.

## Data model

SQLite schema v1 (`lib/core/database/tables.dart`, snapshot in
`drift_schemas/drift_schema_v1.json`):

- **winter_arc_sessions**: `id` PK, `start_date`, `end_date` (ISO text),
  `status` (`setup` | `active` | `completed`), `created_at`, `started_at?`
- **habits**: PK (`session_id`, `id`). Columns: `title`, `type` (`binary` |
  `count` | `duration`), `target` (>0), `unit?`, `icon_key`, `enabled`,
  `sort_order`, `created_at`. FK → sessions.
- **daily_habit_progress_entries**: PK (`session_id`, `habit_id`, `date`).
  Columns: `current_value` (≥0), `completed`, `completed_at?`, `updated_at`.
  FK → habits.
- **xp_transactions**: `id` PK, `session_id`, `source_key`, `reason`,
  `amount`, `habit_id?`, `date`, `created_at`. **UNIQUE (`session_id`,
  `source_key`)**.

Enums are stored by name. Renaming an enum value requires a migration.
`PRAGMA foreign_keys = ON` is set on every open.

Domain models: `WinterArcSession` (with `positionOn(date)` →
`ArcNotStarted | ArcInProgress(dayNumber) | ArcFinished`), `Habit`,
`DailyHabitProgress`, `XpAward`, and the `DaySummary` read model with
`DayCompletion`.

### Date model

- An arc lasts `WinterArcRules.lengthInDays = 92` days, inclusive.
- **Day 1 is the local calendar date when the user taps "Start Winter Arc".**
  The end is Day 1 + 91 days. Starting on Oct 1 gives Oct 1 → Dec 31 exactly.
  Starting later gives a personal 92-day arc, e.g. Oct 2 → Jan 1. The setup
  session's provisional dates are recomputed at start.
- The day index changes at local midnight. `Clock` is injected everywhere, and
  tests drive time explicitly.

## Boot flow

`bootLocationProvider` reads the latest session from SQLite once at launch:

| Persisted state | Route |
|---|---|
| no session | `/onboarding` |
| session `setup` (onboarding done, habits not confirmed) | `/setup` |
| session `active` / `completed` | `/today` |

Navigation uses `context.go`, so Back never returns to onboarding. If the
boot read fails, a failure screen with **Try again** is shown.

## Completion semantics

| Habit type | Interaction | Completes when |
|---|---|---|
| binary | Tap the row or check. Tap again to undo. | tapped |
| count (Water, step 1) | − / + | value ≥ target |
| duration (Workout etc., step 5 min) | − / + | value ≥ target |

- Values are clamped to `0..target`. + is disabled at the target, − at 0.
- Completing an already-completed habit is a **no-op**: no write, no XP.
- Undo means un-checking a binary habit, or decrementing a numeric habit
  below its target. Either reverts completion and **revokes that habit-day's
  XP**.
- XP: `XpRules.habitCompletion = 15`, keyed `habit_completed:<habit>:<date>`.
  Each habit-day has at most one ledger row. Complete → undo → complete nets
  exactly +15, so toggling cannot farm XP.
- Daily completion % = completed enabled habits / enabled habits, rounded down
  (100% only when all are done). Partial numeric progress doesn't count.
- Actions carry the date the user is looking at. If the day has rolled over,
  the action is rejected (`staleDay`) and Today refreshes. Today also
  refreshes on app resume.
- Actions are rejected when no arc is active, the arc hasn't started or has
  finished, the habit is disabled or unknown, or the action doesn't fit the
  habit type.
- The snackbar shows "+15 XP" with **Undo** only after the write succeeds. The
  haptic fires at the same point.

## Persistence semantics

- Every mutation is a committed SQLite transaction before the UI updates.
  Progress rows and XP rows change atomically together.
- Habit toggles during setup are persisted immediately. Killing the app
  mid-setup keeps the selection (verified on device).
- The database file is `app_flutter/nextrep.sqlite`, opened via
  `drift_flutter` (background isolate).
- Storage errors become `PersistenceFailure`. The UI shows "Couldn't save or
  load your progress" and keeps the last persisted state (widget-tested with a
  failing repository).

### Schema evolution

Generated code (`*.g.dart`) is committed. To change the schema:

1. Edit `tables.dart`, bump `schemaVersion`, and add an `onUpgrade` step in
   `AppDatabase.migration`.
2. `dart run build_runner build`
3. `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/drift_schema_vN.json`
4. Add a migration test (`drift_dev make-migrations` can generate the
   scaffolding from the snapshots).

## Known limitations

- Arc dates follow the start date (see Date model). A fixed seasonal calendar
  (always Oct 1 → Dec 31) would need a product decision.
- Habits can't be edited after starting. Targets aren't user-editable yet.
- No past-day editing. Only today can be tracked.
- "Sleep Before Target" is binary for now. A time-threshold type is future
  work.
- Undo on numeric habits removes one step, which is exact for the shipped
  targets (all multiples of their step).
- `completed` status is reserved: nothing closes an arc after Day 92 yet.
  Today shows "Winter Arc complete" and is read-only.
- iOS is architecturally supported but untested (CocoaPods isn't installed on
  the dev machine. Android is the priority).
- Error reporting is local logging only (`dart:developer`).

## Validation checklist

| Check | Result |
|---|---|
| `dart format .` | clean |
| `flutter analyze` | No issues |
| `flutter test` | 65/65 pass |
| `flutter test --coverage` | 86% of handwritten lib lines (domain 91%, data 99%) |
| `flutter test integration_test -d emulator-5554` | pass (API 36 emulator) |
| `flutter build apk --debug` | built |
| `flutter build apk --release` + `aapt2 dump permissions` | built, no INTERNET permission |
| Manual smoke on emulator (launch → onboarding → setup → start → Today → complete → % updates → force-stop → relaunch → state kept) | pass |

Test map:

- `test/domain/local_date_test.dart`: calendar maths, DST, ISO round trip
- `test/domain/winter_arc_session_test.dart`: day calculation, Oct 1 → Dec 31, boundaries
- `test/domain/habit_progress_rules_test.dart`: completion, idempotency, undo, clamping, XP effects
- `test/domain/day_completion_test.dart`: percentage semantics
- `test/domain/winter_arc_service_test.dart`: session configuration, habit selection persistence
- `test/domain/habit_tracking_service_test.dart`: concurrent taps, XP once, stale day, arc window
- `test/data/progress_repository_test.dart`: round trip, unique ledger, failure wrapping, constraints
- `test/data/restart_restoration_test.dart`: close/reopen DB file, boot routing and state restored
- `test/features/day_one_flow_test.dart`: full UI flow + relaunch, Undo, storage failure UI
- `integration_test/day_one_smoke_test.dart`: the same flow on a real device

## Phase 2 handoff

Recommended Phase 2: **"Habit loop depth"**

1. Streaks (per habit + perfect days), derived from `daily_habit_progress_entries`.
2. Levels from the XP ledger (pure `LevelRules` over `totalXp`). Perfect-day bonus XP keyed `perfect_day:<date>`.
3. Minimum Day mode: a reduced-target day type stored per date.
4. Habit editing after start (targets, enable/disable) with history-safe semantics.
5. Bottom-nav shell (`StatefulShellRoute`): Today + Journey (92-day grid from stored progress).
6. First motion/haptics pass, driven only by persisted transitions.
7. Schema v2 migration + migration tests using `drift_schemas/`.
