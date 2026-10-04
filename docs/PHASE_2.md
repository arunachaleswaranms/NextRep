# Phase 2 — Habit loop depth

## Goals

Phase 2 turns the Day 1 checklist into a progression system. It builds on the
Phase 1 architecture and does not replace it:

- per-habit streaks, and Perfect Days with their own streak and total
- a +30 XP Perfect Day bonus, and levels derived from the XP ledger
- Minimum Day: a one-way, reduced-target mode for today
- history-safe habit editing (name, targets, enable/disable) after the start
- a bottom-navigation shell (Today, Journey) and a data-driven Journey v1
- schema v2 with a real, tested v1 → v2 migration
- a restrained first layer of motion and haptics

Out of scope: the cinematic Journey art, snow, aurora, fire, parallax,
achievements, journal, notifications, sync, accounts, health integrations,
analytics. No network permission was added.

## Architecture changes

The direction of control is unchanged, but there is now **one write path**
for anything that changes the current day:

```
user action (habit tap, Minimum Day, habit edit)
  → controller (SerialQueue)
  → HabitTrackingService: validate (active arc, date == today, in window)
  → ProgressRepository.commitDay — one SQLite transaction:
       read DayContext (habits + revisions, mode, progress, ledger rows of the date)
       → DayRules.settle (pure): new progress + completion reconciliation
                                 + exact ledger diff
       → apply the settlement, re-sum XP
  → DayCommit (what was written, XP before / after)
  → controller re-reads persisted truth → UI
  → haptics / celebration (from the commit, never from timing)
```

| Area | Change |
|---|---|
| `domain/progress/day_rules.dart` | **New single XP authority.** `DayRules.settle` turns a requested `DayChange` (progress rows, mode, revision, rename) into a `DaySettlement`. The ledger for a date is a pure function of that date's state. |
| `domain/progress/habit_progress_rules.dart` | Now takes the **effective target**. It only decides progress. The per-habit `xpEffect` was removed so XP has a single source (`DayRules`). Increments never lower a value that is already above the target. |
| `domain/habit/habit_config.dart` | `HabitConfig`, `HabitRevision` and `HabitHistory.configOn(habit, date)` / `planFor(date, mode)` provide the effective, dated configuration. |
| `domain/progress/arc_history.dart` | `ArcRecords` (stored facts) → `ArcHistory` (derived): day records, streaks, Perfect Day stats, Journey. |
| `domain/progress/streak_rules.dart` | Streaks are computed from marks: hit / miss / skip / pending. |
| `domain/xp/level_rules.dart` | Levels are derived from total XP and never stored. |
| `domain/journey/` | `JourneyDayState`, `JourneyDay`, `JourneyOverview`. |
| `ProgressRepository` | `loadArc` (consistent snapshot), `commitDay` (atomic read-settle-write). `applyTransition` was replaced by `commitDay`. |
| `app/router` | `StatefulShellRoute.indexedStack` with Today and Journey branches. |
| `app/arc_refresh.dart` | A counter bumped after persisted changes. Journey watches it, so it re-reads after a change on Today or in the habit editor. |

## Schema v2

`schemaVersion = 2`. Snapshot: `drift_schemas/drift_schema_v2.json` (v1 is
unchanged).

| Table | Change |
|---|---|
| `habits` | New `minimum_target INTEGER NOT NULL DEFAULT 1 CHECK (minimum_target BETWEEN 1 AND target)`. It is the last column, matching where `ALTER TABLE ADD COLUMN` puts it. `target`, `minimum_target` and `enabled` are now the **baseline** (setup) configuration, effective from Day 1. |
| `habit_revisions` (new) | PK (`session_id`, `habit_id`, `effective_from`). Columns: `target`, `minimum_target`, `enabled`, `created_at`. Checks: target > 0, 1 ≤ minimum ≤ target. FK → habits, cascade. |
| `day_modes` (new) | PK (`session_id`, `date`). Columns: `mode` (`normal` \| `minimum`), `changed_at`. FK → sessions, cascade. No row means a Normal Day. |
| `xp_transactions` | No DDL change. New reason value `perfectDay`. |

Nothing derived is stored. Streaks, levels, Perfect Day status and Journey
states are all computed from these tables.

## v1 → v2 migration

`AppDatabase._from1To2` runs through drift's `stepByStep` with the generated,
frozen `Schema2` shape (`lib/core/database/schema_versions.dart`), so the step
keeps working when v3 arrives. It is **additive only**:

1. `ADD COLUMN habits.minimum_target`, then backfill the starter minimums
   (workout 10, water 3, learning 5, english 5, meditation 5, binary 1). Each
   value is capped at the habit's target. Unknown habits keep their full target.
2. `CREATE TABLE habit_revisions` and `day_modes`. Both start empty: every
   existing day is normal and uses the baseline configuration, which is
   exactly what v1 meant.
3. Backfill `perfect_day:<date>` (+30) for every stored date where all
   enabled habits had a completed row. v1 had no revisions or Minimum Days,
   so that is exactly the Phase 2 Perfect Day definition. `INSERT OR IGNORE`
   on the unique key means it can never duplicate. Without this step, earlier
   Perfect Days would show as Perfect but carry no bonus.

The step never rewrites or deletes existing session, habit, progress or
ledger rows. Constants in the SQL are frozen at their v2 values on purpose.

**Tests** (`test/data/migration_test.dart`, drift `SchemaVerifier`):
- An empty v1 database migrates to exactly the v2 snapshot.
- A realistic v1 fixture (active arc, setup toggles, 3 days of progress, 8
  ledger rows) migrates with all of the following kept: session, habits,
  enabled flags, progress rows, ledger rows.
- Correct minimum targets, a single Day 1 bonus, and empty new tables.
- Today and Journey read the migrated history correctly.
- Phase 2 writes work after migration (edit, Minimum Day, tracking), and
  history stays stable.
- A v1 session still in setup migrates and can start.

On a device: the Phase 1 release APK from `main` was installed, a perfect Day
1 was recorded (60 XP), and the Phase 2 release APK was installed over it.
The app opened in the new shell with everything intact and the backfilled
bonus applied (90 XP).

## Effective configuration (history model)

- `configOn(habit, date)` is the latest revision with `effective_from ≤ date`,
  otherwise the habit's baseline.
- After the arc has started, configuration changes **only** upsert a revision
  with `effective_from = today`. A second edit on the same day replaces that
  day's revision. No API can write a revision for another date, so the
  configuration of every past date is immutable.
- Setup (before the start) still writes the baseline directly, as in Phase 1.
- `DayRecord` = mode + the habits enabled that day + their effective targets
  + stored progress. The stored `completed` flag is kept equal to
  `value ≥ effective target` while the date is today, and is never
  re-evaluated afterwards.
- Renaming a habit is cosmetic and applies to every day. The title lives on
  `habits`.

## Habit edit semantics

Editable after the start: name, normal target, minimum target, enabled.

| Rule | Behaviour |
|---|---|
| Applies from | today onwards. Past days keep their configuration. |
| Validation | name 1–40 chars. Target 1..50 (count) or 1..300 (duration). 1 ≤ minimum ≤ target. Binary targets stay 1. At least one habit must stay enabled. |
| Progress today | Kept unchanged. Completion is re-evaluated against the new effective target. |
| Habit XP today | Granted if the habit is now complete, revoked if not. |
| Disable today | The habit leaves today's plan. Its XP for today is revoked, but its progress row is kept. Re-enabling the same day restores both. |
| Perfect Day bonus | Reconciled in the same transaction (e.g. raising a target revokes it, lowering it back restores it once). |
| Past days | Not editable. Rejected with `staleDay`. |

## Streak semantics

Only challenge dates from Day 1 to `min(today, end)` are evaluated. Future
dates and dates outside the arc never count.

**Per habit:** each date is

| Mark | When |
|---|---|
| hit | the habit was enabled and completed (against that day's normal or minimum target) |
| skip | the habit was not enabled that day: neither counts nor breaks |
| pending | today, not done yet: does not break |
| miss | an eligible past day not completed: resets |

`current` is the run alive today. `best` is the longest run in the arc.

**Perfect Days:** a perfect date is a hit. Today counts as pending while it is
a normal, unfinished day. Every other date is a miss, including any Minimum
Day (today as well, once switched). The total is the number of Perfect Days.

## Perfect Day and XP

- **Perfect Day** = a Normal Day + at least one enabled habit + every enabled
  habit complete against that day's targets.
- `XpRules.habitCompletion = 15` per completed enabled habit-day, keyed
  `habit_completed:<habit>:<date>`.
- `XpRules.perfectDayBonus = 30` per Perfect Day, keyed
  `perfect_day:<YYYY-MM-DD>`.
- The ledger keeps one row per key (unique index plus `INSERT OR IGNORE`).
  Settling an unchanged day writes nothing, so refreshes, restarts, repeated
  taps and concurrent calls (serialised by Drift transactions) cannot
  duplicate XP.
- Undoing a habit on a Perfect Day revokes +15 and +30. Re-completing
  restores both, once.

## Levels

`LevelRules`: `xpPerLevel = 250`, `level = 1 + totalXp ~/ 250`. It exposes
level, total XP, XP into the level, XP for the level, XP to the next level, and
a progress ratio. A level-up is detected by comparing the XP before and after
from the same `commitDay` transaction (`LevelRules.levelUp`). Nothing about
levels is persisted.

## Minimum Day

- `DayMode { normal, minimum }`, persisted per date in `day_modes`.
- Only today can be switched (`staleDay` otherwise), only while the arc runs,
  and only on a normal day that is **not already perfect**
  (`dayAlreadyPerfect`, which protects an earned bonus).
- **One-way.** No API switches back to normal. Activating again is a no-op.
- Effective targets become each habit's minimum target. Progress is never
  reduced. Habits already meeting their minimum complete immediately and earn
  +15, in the same transaction.
- Minimum completions count for habit streaks. A Minimum Day is never a Perfect
  Day (no +30) and breaks the Perfect Day streak.
- The next day starts as normal again.
- UI: "Having a rough day?" card → explanation sheet with a preview of the
  reduced goals → "Switch to Minimum Day" (or "Not now"). Today then shows a
  MINIMUM DAY badge, a warm recovery banner, MINIMUM on each habit and the
  reduced targets.

## Journey state model

Each of the arc's days has exactly one `JourneyDayState`:

| State | Condition |
|---|---|
| `future` | date > today |
| `perfect` | Normal Day, all enabled habits complete (today or past) |
| `minimumComplete` | Minimum Day, all enabled habits at their minimum (today or past) |
| `today` | date == today and neither of the above yet |
| `partial` | past Normal Day with some progress (any value > 0), not all complete |
| `minimumPartial` | past Minimum Day with some progress, not all complete |
| `missed` | past day (either mode) with no progress at all |

There is no separate "complete" state: on a Normal Day, complete means
Perfect. `isToday` is a flag kept apart from the state. Tapping today or a past
day opens a read-only sheet: Day X, date, mode, habits complete, %, XP earned
that date, Perfect Day yes/no, and per-habit progress against that day's
targets. Future days can't be tapped. Nothing is editable.

## Routing shell

```
/onboarding            plain route (no tabs)
/setup                 plain route (no tabs)
StatefulShellRoute.indexedStack  → ActiveShell (NavigationBar)
  branch 0: /today          TodayScreen
              /today/habits  HabitsScreen (root navigator: covers the tabs)
  branch 1: /journey        JourneyScreen
```

The boot location is unchanged (`/today` for an active arc). The tabs keep
their state (IndexedStack). Journey keeps showing its previous data while
refreshing, so its scroll position survives. Switching tabs clears the
current snackbar. Future tabs are added as branches. No placeholder tabs were
added.

## Motion and haptics

- Tokens: `WinterDurations` and `context.motion`, which returns zero durations
  when `MediaQuery.disableAnimations` (the platform's reduced-motion setting)
  is on.
- Motion: check-icon scale switch, XP count-up, animated progress ring and
  bars, animated level bar, badge and Minimum Day banner transitions, Journey
  tile colour transitions, and the celebration card (fade + scale, auto
  dismissed after 3.2 s or on tap).
- Haptics (`shared/feedback/haptics.dart`): habit complete → light. Perfect
  Day → medium + light. Level up → medium. Minimum Day → selection click.
- Everything runs after `commitDay` succeeds and is derived from the
  `DayCommit` (ledger diff, XP before/after). Animations never decide
  completion, XP, streaks, levels, Perfect Day or Minimum Day.
- New theme tokens: `recovery` (warm Minimum Day accent) and `celebration`
  (Perfect Day / level).

## Validation results (2026-10-03)

| Check | Result |
|---|---|
| `dart format .` | clean |
| `flutter analyze` | No issues |
| `flutter test` | 165 / 165 pass |
| `flutter test --coverage` | 90.5% of handwritten `lib/` lines (domain 96.6%, data 97.1%, features 94.5%) |
| `flutter test test/data/migration_test.dart` | 10 / 10 pass (schema validated against the v2 snapshot) |
| `flutter test integration_test -d emulator-5554` | 2 / 2 pass (Phase 1 Day 1 flow, Phase 2 loop) |
| `flutter build apk --debug` / `--release` | built |
| `aapt2 dump permissions` (release) | no `INTERNET`. The only entry is the app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| Emulator upgrade path (Phase 1 APK → Phase 2 APK) | PASS |
| Emulator manual Phase 2 flow | PASS (see PROJECT_STATE.md) |
| Physical Android device | not tested (manual check still required) |
| iOS | not attempted (CocoaPods missing) |

New test files: `level_rules_test`, `streak_rules_test`,
`habit_history_test`, `day_rules_test`, `arc_history_test`,
`phase2_tracking_test` (service + real SQLite), `data/migration_test`,
`features/phase2_flow_test`, `integration_test/phase2_smoke_test`. Phase 1
tests were adapted to the evolved APIs, with their intent and assertions kept.
Today now uses a non-lazy scroll column, and Phase 1 widget tests scroll to
the 4th habit before tapping it.

## Limitations

- Date model unchanged: Day 1 = the date "Start" is pressed (see open
  decisions).
- A habit edit applies to today. Disabling an unfinished habit, or lowering a
  target, can therefore make *today* a Perfect Day. That follows "changes
  apply from today", but it is a loophole the product may want to close (for
  example, edits effective tomorrow).
- Minimum Day is one-way, and can't be chosen once today is already Perfect.
- No past-day editing, no habit creation or deletion, and no arc close-out
  after Day 92 (the reserved `completed` status still isn't written).
- "Sleep Before Target" remains binary.
- Migration-time Perfect Day backfill uses the v1 definition. That is exact
  for v1 data but would need revisiting if v1 ever had data from other paths.
- Haptics can't be asserted in widget tests. They were checked by code path
  only.

## Phase 3 handoff

Recommended **Phase 3 — "Winter Arc feel"** (visual and retention layer on
top of the proven loop):

1. Cinematic Journey v2 (mountain path) rendering the existing
   `JourneyDayState`s. The domain needs no changes.
2. Winter scene layer in `WinterBackground` (snow, aurora), respecting
   `context.motion`.
3. Achievements derived from `ArcHistory`, using new ledger reasons keyed by
   date, outside `DayRules.managedReasons`.
4. Arc close-out after Day 92 (`completed` status) and a summary screen.
5. Product decisions first: fixed season vs start-date arc, edit timing, and
   reversing Minimum Day.
6. Physical-device pass and the iOS toolchain.

## Schema evolution (updated)

1. Edit `tables.dart`, bump `schemaVersion`.
2. `dart run build_runner build --delete-conflicting-outputs`
3. `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/`
4. `dart run drift_dev schema steps drift_schemas/ lib/core/database/schema_versions.dart`
5. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
6. Add a `fromNToN+1` step to `stepByStep` in `AppDatabase.migration`, and
   migration tests using `SchemaVerifier`.
