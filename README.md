# NextRep — Winter Arc

NextRep is a mobile-first, offline-first habit app. Its first product,
**Winter Arc**, is a gamified 92-day self-improvement challenge (Oct 1 → Dec 31
when started on Oct 1): pick a few daily habits, show up every day, earn XP,
and watch your progress build.

> **Status: Phase 1 — engineering foundation + Day 1 vertical slice.**
> Onboarding → habit setup → start Winter Arc → Today → complete habits →
> progress persists across app restarts. See [docs/PHASE_1.md](docs/PHASE_1.md).

## Architecture

```
lib/
  main.dart                 entry point: opens the DB, ProviderScope
  app/                      composition root, router, theme tokens
    dependencies.dart       Riverpod providers wiring infra → services
    router/                 go_router routes + boot location
    theme/                  WinterColors tokens, spacing, radii, ThemeData
  core/                     framework-agnostic building blocks
    database/               Drift schema, converters, generated code
    errors/                 AppFailure model, reporter, ActionResult
    time/                   LocalDate, Clock abstraction
    utils/                  SerialQueue
  domain/                   pure Dart business logic (owns truth)
    winter_arc/             session model, day calculation, setup/start
    habit/                  Habit, HabitType, starter catalogue
    progress/               progress rules, completion %, tracking service
    xp/                     XP rules, award model
  data/                     Drift implementations of domain repositories
  features/                 UI per feature: controller + screen + widgets
    onboarding/  habit_setup/  today/
  shared/                   reusable widgets + formatting
```

Flow of a habit completion:

```
tap → TodayController (serial queue) → HabitTrackingService (validates)
    → ProgressRepository.applyTransition (one SQLite transaction:
      read → HabitProgressRules.apply → write progress + XP ledger)
    → controller re-reads persisted state → UI rebuilds → haptic/snackbar
```

Animations and haptics only react to persisted results. They never decide
completion or XP.

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
flutter test                     # unit + data + widget tests
flutter test --coverage
flutter test integration_test -d <android-device-id>   # on-device flow
flutter build apk --debug
```

If your default `java` is newer than 21, point Gradle at JDK 21 for the build,
e.g. `JAVA_HOME=$(/usr/libexec/java_home -v 21) flutter build apk --debug`.

## Phase 1 scope

- Dark Winter Arc theme foundation (semantic colour tokens, spacing, radii)
- Onboarding → Habit Setup → Today, with boot routing from persisted state
- Seven starter habits (binary, count and duration types), enable/disable
- Today: day X of 92, date, completion %, XP total, per-habit progress
- Binary: tap to complete / undo. Count & duration: − / + steppers
- Idempotent XP ledger (+15 per habit per day, revoked on undo)
- Local SQLite persistence; survives backgrounding, termination, relaunch
- 65 automated tests + an on-device integration test

## Explicitly deferred

Journey artwork, snow/fire/aurora animation, parallax, achievements, streaks,
levels, analytics dashboard, journal, Minimum Day mode, notifications, cloud
sync, accounts, social, health integrations, AI, backend, payments, and an
advanced theme engine. See [docs/PHASE_1.md](docs/PHASE_1.md#phase-2-handoff).

## Privacy

Local-only: no backend, analytics, telemetry, ads or trackers. The release
APK requests no network permission (checked with `aapt2 dump permissions`:
the only entry is AndroidX's app-private
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). `INTERNET` appears only in the
debug/profile manifests, which Flutter tooling needs for hot reload.
