# NextRep

**A private, local-first Winter Arc: a 92-day self-improvement challenge
for your daily habits.**

> **Status: v1.0.0 release candidate, pending owner publication.**
> Android APKs are published on the
> [GitHub Releases](https://github.com/arunachaleswaranms/NextRep/releases)
> page.

## What is NextRep?

NextRep's **Winter Arc** is a 92-day challenge: pick a few daily habits,
show up every day, earn XP, and climb from a frozen trail to a warm summit.
Two kinds of Arc:

- **Rolling 92-Day Arc**: Day 1 is the day you press Start.
- **Seasonal Winter Arc**: 1 October – 31 December. Set it up in
  September, or join the season already in progress. A late join keeps the
  season's day numbers, and the days before it are neutral.

NextRep is **local-first and private**. There's no account, no server, no
analytics and no cloud sync. Everything stays on your phone.

## Features

- **Habits**: a catalogue of templates plus your own custom habits (done /
  not done, counts, minutes, or "before a time"), up to 12 per arc. Goal
  edits apply from the next day.
- **Sleep Before Target**: a morning check-in of last night's bedtime
  against your goal.
- **Today**: check off habits, with streaks, XP, levels and a Perfect Day
  bonus when every habit is done.
- **Minimum Day**: on a hard day, switch today to each habit's minimum and
  keep your streaks.
- **Journey**: your 92 days on a mountain path in six chapters, with
  milestones.
- **15 achievements**, with celebrations.
- **Journal**: a 20-second nightly reflection (mood, one win, one thing to
  improve).
- **Arc History and summaries**: every finished arc, read-only, with its
  Journey and Journal. Start the next arc from the last one's setup.
- **Insights** across arcs: consistency, Perfect and Minimum Days, XP,
  per-habit completion and moods.
- **Reminders**: an optional daily nudge and an evening reflection prompt,
  scheduled on the device. Off by default.
- **Backup & restore** to a `.nextrep` file.
- A winter scene that respects reduced motion, large-text support and
  screen-reader labels.

## Download

Android APKs are published on the
[GitHub Releases](https://github.com/arunachaleswaranms/NextRep/releases)
page as `NextRep-v<version>-android.apk`, each with a `.sha256` checksum
file.

**v1.0.0: release candidate, pending owner publication.**

Only download NextRep from this repository's Releases page. How to check a
download: [docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md).

There is no iPhone release. The app builds for iOS from source (below).

## Install on Android

Requires Android 7.0 or newer.

1. Download `NextRep-v<version>-android.apk` from
   [GitHub Releases](https://github.com/arunachaleswaranms/NextRep/releases)
   on your phone.
2. Open the downloaded file. Android may ask you to allow your browser or
   file manager to **install unknown apps**.
3. Allow it **only for the app you used to open the APK** (for example
   your browser or Files).
4. Tap **Install**, then open NextRep.
5. If you like, turn the "install unknown apps" permission off again
   afterwards in Settings.

You don't need to change any other security setting. Leave Google Play
Protect on.

## Updating

1. Download the newer NextRep APK from the Releases page.
2. Open it and tap **Update**. It installs over your current NextRep.
3. **Don't uninstall first.** Uninstalling deletes the app's data.

Your data stays because every official release is signed with the same
key, and Android only accepts an update signed with it. Before a major
upgrade, export a backup anyway (below).

If Android refuses the update, don't uninstall to force it. Get the APK
again from the Releases page and check it
([docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md)).

## Backup & Restore

Open **Data & Backup** from Arc History (or from onboarding on a new
device):

- **Export Backup** writes everything (arcs, habits, history, XP,
  achievements and your Journal reflections) to a
  `nextrep-backup-YYYY-MM-DD.nextrep` file, wherever you choose in the
  system file dialog.
- **Restore Backup** checks the whole file first, shows what it contains,
  and asks before replacing the data on this device. Reminders come back
  turned off. Turn them on again if you want them.

**Backups are not encrypted by NextRep.** Anyone who can open the file can
read your reflections. Keep it somewhere you trust. The file includes a
checksum to detect accidental damage; it isn't a security feature.

## Privacy

No account, no server, no analytics, telemetry, ads or trackers, and no
cloud sync. The Android release doesn't request the `INTERNET` permission.
Reminders are local notifications with generic text. Your phone's own
system backup may include app data if you have it turned on.

Full details: [PRIVACY.md](PRIVACY.md).

## Build from source

Requires Flutter stable 3.47.x. Android builds need JDK 17–21. iOS builds
use Swift Package Manager, so CocoaPods isn't needed.

```bash
git clone https://github.com/arunachaleswaranms/NextRep.git
cd NextRep
flutter pub get
flutter run            # on a connected device or emulator
flutter test           # run the tests
```

An APK for your own device:

```bash
flutter build apk --debug
```

`flutter build apk --release` without a signing configuration is also
debug-signed. To sign with your own key, see
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md#building-your-own-copy).
A self-built APK can't update an official install (and vice versa),
because the signing keys differ. Move data between them with a backup.

Generated Drift code is committed. Only run
`dart run build_runner build` after editing database tables. If your
default `java` is newer than 21, point Gradle at JDK 21, e.g.
`JAVA_HOME=$(/usr/libexec/java_home -v 21) flutter build apk --debug`.

## License

[MIT](LICENSE) © 2026 Arunachaleswaran M S.

---

# Development

The rest of this README is for people working on the code.

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
    winter_arc/             session model, arc kinds and seasonal rules,
                            participation, current-arc resolution,
                            setup/start/new arc, arc close-out
    habit/                  Habit, dated config (HabitHistory), edit rules,
                            NightTime, template catalogue, setup rules
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

## Quality gates

```bash
dart format .
flutter analyze
flutter test                     # unit + data + migration + widget tests
flutter test test/data/migration_test.dart test/data/migration_v3_test.dart \
  test/data/migration_v4_test.dart test/data/migration_v5_test.dart  # → v5
flutter test test/domain/backup_format_test.dart test/domain/backup_v2_test.dart \
  test/data/backup_restore_test.dart test/data/backup_v2_restore_test.dart \
  test/domain/arc_deletion_test.dart test/domain/insight_rules_test.dart
flutter test test/domain/seasonal_arc_test.dart test/domain/participation_test.dart \
  test/domain/time_before_test.dart test/domain/setup_habits_test.dart  # Phase 6
flutter test test/app/day_change_test.dart test/domain/date_edges_test.dart \
  test/features/phase7_lifecycle_test.dart \
  test/features/phase7_accessibility_test.dart                          # Phase 7
flutter test --coverage
flutter test integration_test -d <device-id> --no-uninstall   # on-device flows
flutter build apk --debug
flutter build apk --release      # debug-signed unless android/key.properties exists
flutter build appbundle --release
flutter build ios --simulator
flutter build ios --release --no-codesign
```

Release signing is documented in
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md). Brand assets come
from `flutter test tool/brand_assets/generate_brand_assets.dart`. A
synthetic backup for store screenshots comes from
`SCREENSHOT_DATE=<device date> flutter test tool/screenshots/generate_screenshot_backup.dart`
(see [docs/STORE_METADATA.md](docs/STORE_METADATA.md#screenshots)).

If your default `java` is newer than 21, point Gradle at JDK 21 for the build,
e.g. `JAVA_HOME=$(/usr/libexec/java_home -v 21) flutter build apk --debug`.

## CI

[`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) runs on
every pull request and push to `main`:

- format check and analyze
- migration tests (v1 → v5) and backup format tests (v1 and v2)
- the release qualification tests, then all tests
- Android debug and release builds. The CI release APK is debug-signed (CI
  holds no signing secrets). It is a compile and permission check only and
  is never distributed. Official APKs are built and signed on the
  maintainer's machine ([docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md)).
- a release permission audit that fails on `INTERNET`, exact-alarm or
  broad storage permissions

## Explicitly deferred

Custom seasons or lengths, adding or deleting habits in a running arc, a
Minimum Day policy for clock-time habits, merge-import, encrypted backups,
cloud sync, accounts, social, health integrations, AI, backend, payments,
cancelling or deleting an active arc. See
[docs/PHASE_6.md](docs/PHASE_6.md#phase-7-handoff).

## Project history

NextRep was built in reviewed phases, one pull request each. The
user-facing history is in [CHANGELOG.md](CHANGELOG.md). Per-phase
implementation and qualification records:
[1](docs/PHASE_1.md), [2](docs/PHASE_2.md), [3](docs/PHASE_3.md),
[4](docs/PHASE_4.md), [5](docs/PHASE_5.md), [6](docs/PHASE_6.md),
[7](docs/PHASE_7.md), [8](docs/PHASE_8.md),
[8.5](docs/PHASE_8_5_PHYSICAL_ANDROID.md), [9](docs/PHASE_9.md).
Current status: [PROJECT_STATE.md](PROJECT_STATE.md).

Release documents:

- [docs/DIRECT_DISTRIBUTION.md](docs/DIRECT_DISTRIBUTION.md): official
  APKs and how to check them
- [docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md): the release key
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)
- [docs/releases/](docs/releases/): release notes

Google Play and App Store publication is not planned.
[docs/STORE_READINESS.md](docs/STORE_READINESS.md) and
[docs/STORE_METADATA.md](docs/STORE_METADATA.md) are kept as Phase 7–8
history.
