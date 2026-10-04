# NextRep — Winter Arc

NextRep is a mobile-first, offline-first habit app. Its first product,
**Winter Arc**, is a gamified 92-day self-improvement challenge: pick a few
daily habits, show up every day, earn XP, and climb from a frozen trail to a
warm summit. Day 1 is the day you press Start (Oct 1 → Dec 31 when started on
Oct 1).

> **Status: Phase 5 — Data safety & insight.** A portable, checksummed
> backup file, a validated, transactional full restore, deleting a
> completed arc, cancelling a setup, and on-device Insights across arcs
> (consistency, habits, moods). Schema still v4. See
> [docs/PHASE_5.md](docs/PHASE_5.md), and [docs/PHASE_4.md](docs/PHASE_4.md),
> [docs/PHASE_3.md](docs/PHASE_3.md), [docs/PHASE_2.md](docs/PHASE_2.md) and
> [docs/PHASE_1.md](docs/PHASE_1.md) for the earlier phases.

## Architecture

```
lib/
  main.dart                 entry point: opens the DB, ProviderScope
  app/                      composition root, router, theme tokens
    dependencies.dart       Riverpod providers wiring infra → services
    arc_status.dart         lifecycle status → router redirect
    router/                 go_router routes, boot location, redirects
    theme/                  WinterColors tokens, spacing, radii, ThemeData
  core/                     framework-agnostic building blocks
    database/               Drift schema, migrations, converters, generated code
    errors/                 AppFailure model, reporter, ActionResult
    time/                   LocalDate, Clock abstraction
    utils/                  SerialQueue
  domain/                   pure Dart business logic (owns truth)
    winter_arc/             session model, current-arc resolution,
                            setup/start/new arc, arc close-out
    habit/                  Habit, dated config (HabitHistory), edit rules
    progress/               progress + day rules, streaks, arc history,
                            Minimum Day, tracking service, arc summary
    journey/                Journey day states, milestones, chapters
    achievement/            catalog, rules, reconciliation service
    reflection/             daily reflections (Journal), validation
    reminder/               preferences, pure planner, scheduler interface
    history/                Arc History read model
    backup/                 backup format (codec, checksum), validator,
                            store interface, export / restore service
    insights/               pure cross-arc insight rules and service
    xp/                     XP rules, LevelRules
  data/                     Drift repositories, backup store, system file
                            picker adapter, local notification scheduler
  features/                 UI per feature: controller + screen + widgets
    onboarding/  habit_setup/  new_arc/  shell/  today/  habits/  journey/
    journal/  history/  reminders/  achievements/  celebration/  summary/
    backup/  insights/
  shared/                   reusable widgets, formatting, winter_scene/
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

Several arcs can exist, but at most one is unfinished (setup or active).
Use cases resolve the arc explicitly (`CurrentArcService`): writes only reach
the active arc, and history screens load one arc by the id in their route
(`/arc/:sessionId/...`), never "the latest".

Streaks, levels, Perfect Days and Journey states are derived from stored
history, never stored. Achievement unlocks are derived too, then persisted
by an idempotent reconciliation outside the habit transaction. Animations
and haptics only react to persisted results. They never decide completion,
XP or achievements.

**Stack:** Flutter 3.47 / Dart 3.13 · Riverpod 3 (state + DI) · Drift 2
(SQLite) · go_router · intl · flutter_local_notifications (local reminders
only) · file_picker (system document UI for backups) · crypto (SHA-256).

## Setup

Requires Flutter stable (3.47.x). For Android builds use JDK 17–21. iOS
builds use Swift Package Manager (enabled in this Flutter install), so
CocoaPods isn't needed.

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
flutter test test/data/migration_test.dart test/data/migration_v3_test.dart \
  test/data/migration_v4_test.dart  # v1/v2/v3 → v4
flutter test test/domain/backup_format_test.dart \
  test/data/backup_restore_test.dart test/domain/arc_deletion_test.dart \
  test/domain/insight_rules_test.dart   # Phase 5 data safety + insights
flutter test --coverage
flutter test integration_test -d <device-id> --no-uninstall   # on-device flows
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
- Habit editing after the start (name, targets, enable). Past days keep
  their configuration. Phase 3 moved goal edits to the next day.
- Today / Journey bottom-nav shell. Journey v1 is a 92-day grid of
  deterministic day states with a read-only day detail.
- Schema v2 with a tested v1 → v2 migration.
- First motion/haptics layer. Respects the reduced-motion setting.

**Phase 3:**
- Winter scene (sky, aurora, mountains, camp and shelter light, trail,
  snow). It's programmatic, offline, reduced-motion aware and stops in the
  background.
- Today hero and new habit cards. Journey v2: 92 days on a mountain path
  in six chapters, with milestone flags.
- 10 achievements with persisted unlocks, an Achievements screen and
  queued celebration cards. Achievements never grant XP.
- Goal and on/off edits apply from the next day; renames apply now. On
  Day 92 only renames are possible.
- The arc closes after Day 92. A completed arc is read-only and opens on
  the End-of-Arc summary.
- Schema v3 (`achievement_unlocks`) with tested v2 → v3 and v1 → v2 → v3
  migrations. GitHub Actions CI.

**Phase 4:**
- Start New Arc from the completed summary: reuse the last setup (each
  habit's final configuration) or start fresh, then Habit Setup. Returning
  users skip onboarding. At most one arc in setup or running; a completed
  arc is never written again.
- Tabs: Today · Journey · Journal · History. Arc History lists every arc
  newest first. A past arc opens its own read-only summary, Journey,
  Journal and achievements.
- Journal: a 20-second nightly reflection (mood, one win, one thing to
  improve). Only today is editable; past entries and completed arcs are
  read-only.
- Reminders: an optional daily nudge and evening reflection prompt. Off by
  default, local and inexact, only while an arc runs, deep-linking to
  Today or the Journal (also on cold launch).
- 15 achievements (Looking Inward, Seven Check-ins, Adaptable, Ten Clean
  Sweeps, Stronger Every Day added).
- Schema v4 (`daily_reflections`, `reminder_preferences`, a unique index
  for one unfinished arc) with tested v3 → v4 and full-chain migrations.

**Phase 5:**
- **Data & Backup** (from Arc History, and from onboarding on a new
  device). Export writes `nextrep-backup-YYYY-MM-DD.nextrep`, a versioned
  (`formatVersion` 1), canonical JSON file with a SHA-256 checksum, through
  the system save dialog. The file holds reflections and is **not
  encrypted**, and the app says so before every export.
- **Restore** validates the whole file first (size, product, version,
  checksum, every field, every cross-record rule). It previews the counts,
  asks again when the device has data, then replaces everything in one
  transaction: any failure rolls back. Reminders come back off. The app then
  reloads from the restored data.
- **Delete Arc** for completed arcs (from the summary's menu, with a
  destructive confirmation) and **Cancel setup** for an arc not yet
  started. Both are transactional; other arcs and reminder preferences are
  untouched.
- **Insights** (from Arc History): weighted consistency across arcs,
  Perfect and Minimum Day totals, XP and levels, per-habit completion over
  enabled days (one habit per stable id), and the Journal's mood counts and
  timeline. Computed on the device, descriptive only.
- No schema change (still v4); the full migration chain still passes.

## Explicitly deferred

Seasonal (1 Oct → 31 Dec) preset, merge-import, encrypted backups, cloud
sync, accounts, social, health integrations, AI, backend, payments,
cancelling or deleting an active arc. See
[docs/PHASE_5.md](docs/PHASE_5.md#phase-6-handoff).

## CI

[`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) runs on
every pull request and push to `main`: format check, analyze, migration
tests, all tests, and an Android debug build.

## Privacy

Local-only: no backend, analytics, telemetry, ads or trackers.

- **Reflections** are private text stored only in the on-device SQLite
  database. They are never uploaded, logged or put in error reports
  (reflection storage errors keep only the error type, because SQLite
  errors can quote the values). Notifications carry generic text only.
- **Reminders** are scheduled locally by the OS. There's no push service.
- **Backups** leave the device only when you export one, to the place you
  pick in the system file UI. They are checksummed (to detect damage), not
  encrypted. Backup errors never quote the file; restoring never turns
  reminders on.
- **Release APK permissions** (`aapt2 dump permissions`):
  - `POST_NOTIFICATIONS` and `VIBRATE` (notifications)
  - `RECEIVE_BOOT_COMPLETED` (restore reminders after a reboot)
  - AndroidX's app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
- No `INTERNET`, no exact-alarm permission and no storage permission
  (`MANAGE/READ/WRITE_EXTERNAL_STORAGE`): backups use the system document
  picker. `INTERNET` appears only in the debug/profile manifests, which
  Flutter tooling needs for hot reload.
