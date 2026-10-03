# NextRep — Winter Arc

NextRep is a mobile-first, offline-first habit app. Its first product,
**Winter Arc**, is a gamified 92-day self-improvement challenge (Oct 1 → Dec 31
when started on Oct 1): pick a few daily habits, show up every day, earn XP,
and watch your progress build.

> **Status: Phase 2 — habit loop depth.** Streaks, Perfect Days (+30 XP),
> levels, Minimum Day, history-safe habit editing, a Today / Journey tab
> shell and schema v2 with a tested migration. See
> [docs/PHASE_2.md](docs/PHASE_2.md) (and [docs/PHASE_1.md](docs/PHASE_1.md)
> for the foundation).

## Architecture

```
lib/
  main.dart                 entry point: opens the DB, ProviderScope
  app/                      composition root, router, theme tokens
    dependencies.dart       Riverpod providers wiring infra → services
    router/                 go_router routes + boot location
    theme/                  WinterColors tokens, spacing, radii, ThemeData
  core/                     framework-agnostic building blocks
    database/               Drift schema, migrations, converters, generated code
    errors/                 AppFailure model, reporter, ActionResult
    time/                   LocalDate, Clock abstraction
    utils/                  SerialQueue
  domain/                   pure Dart business logic (owns truth)
    winter_arc/             session model, day calculation, setup/start
    habit/                  Habit, dated config (HabitHistory), edit rules
    progress/               progress + day rules, streaks, arc history,
                            Minimum Day, tracking service
    journey/                Journey day states and overview
    xp/                     XP rules, LevelRules
  data/                     Drift implementations of domain repositories
  features/                 UI per feature: controller + screen + widgets
    onboarding/  habit_setup/  shell/  today/  habits/  journey/
  shared/                   reusable widgets + formatting
```

Every change to the current day (habit action, Minimum Day, habit edit)
takes the same path:

```
action → controller (serial queue) → HabitTrackingService (validates)
    → ProgressRepository.commitDay (one SQLite transaction:
      read day → DayRules.settle (pure: progress, completion, XP diff)
      → write progress / mode / revision + XP ledger)
    → controller re-reads persisted state → UI rebuilds
    → haptics / celebration derived from the commit
```

Streaks, levels, Perfect Days and Journey states are derived from stored
history, never stored. Animations and haptics only react to persisted
results. They never decide completion or XP.

**Stack:** Flutter 3.47 / Dart 3.13 · Riverpod 3 (state + DI) · Drift 2
(SQLite) · go_router · intl.

## Setup

Requires Flutter stable (3.47.x). For Android builds use JDK 17–21.

```bash
flutter pub get
# Only needed after editing Drift tables (generated code is committed):
dart run build_runner build
```

Run on a device or emulator:

```bash
flutter devices
flutter run -d <device-id>
```

## Quality gates

```bash
dart format .
flutter analyze
flutter test                     # unit + data + migration + widget tests
flutter test test/data/migration_test.dart   # schema v1 → v2
flutter test --coverage
flutter test integration_test -d <android-device-id>   # on-device flow
flutter build apk --debug
flutter build apk --release
```

If your default `java` is newer than 21, point Gradle at JDK 21 for the build,
e.g. `JAVA_HOME=$(/usr/libexec/java_home -v 21) flutter build apk --debug`.

## What's in the app

**Phase 1:** dark Winter Arc theme tokens. Onboarding → Habit Setup → Today
with boot routing. Seven starter habits (binary, count, duration).
Idempotent XP ledger (+15 per habit-day, revoked on undo). Local SQLite that
survives restarts.

**Phase 2:**
- Per-habit current/best streaks. Perfect Day streak, best and total.
- Perfect Day bonus (+30 XP once per Normal Day with every habit done,
  revoked on undo). Levels every 250 XP, derived from the ledger.
- Minimum Day: a deliberate, one-way switch of today to each habit's minimum
  target. Keeps streaks, never a Perfect Day.
- Habit editing after the start (name, targets, enable). Applies from today,
  and past days keep their configuration.
- Today / Journey bottom-nav shell. Journey v1 is a 92-day grid of
  deterministic day states with a read-only day detail.
- Schema v2 with a tested v1 → v2 migration.
- First motion/haptics layer. Respects the reduced-motion setting.

## Explicitly deferred

Cinematic Journey artwork, snow/fire/aurora animation, parallax,
achievements, analytics dashboard, journal, notifications, cloud sync,
accounts, social, health integrations, AI, backend, payments. See
[docs/PHASE_2.md](docs/PHASE_2.md#phase-3-handoff).

## Privacy

Local-only: no backend, analytics, telemetry, ads or trackers. The release
APK requests no network permission (checked with `aapt2 dump permissions`:
the only entry is AndroidX's app-private
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). `INTERNET` appears only in the
debug/profile manifests, which Flutter tooling needs for hot reload.
