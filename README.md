# NextRep — Winter Arc

NextRep is a mobile-first, offline-first habit app. Its first product,
**Winter Arc**, is a gamified 92-day self-improvement challenge: pick a few
daily habits, show up every day, earn XP, and climb from a frozen trail to a
warm summit. Two kinds of Arc:

- **Rolling 92-Day Arc**: Day 1 is the day you press Start.
- **Seasonal Winter Arc**: 1 October – 31 December. Set it up in
  September, or join the season already in progress; a late join keeps
  the season's day numbers and the days before it are neutral.

> **Status: Phase 8: Store launch & physical qualification.** Software
> release candidate, qualified on the release build in the emulator and
> simulator. Store submission still has manual gates:
>
> - production identifiers, the first version and the Android backup
>   policy (owner decisions)
> - signing
> - physical Android / iPhone passes (TalkBack, VoiceOver)
> - the privacy-policy URL
> - iPhone screenshots
>
> See [docs/PHASE_8.md](docs/PHASE_8.md),
> [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md),
> [docs/STORE_READINESS.md](docs/STORE_READINESS.md),
> [PRIVACY.md](PRIVACY.md) and [CHANGELOG.md](CHANGELOG.md). Earlier
> phases: [7](docs/PHASE_7.md), [6](docs/PHASE_6.md), [5](docs/PHASE_5.md),
> [4](docs/PHASE_4.md), [3](docs/PHASE_3.md), [2](docs/PHASE_2.md),
> [1](docs/PHASE_1.md).

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

**Phase 6:**
- **Arc kinds**: Rolling 92-Day (unchanged) and the **Seasonal Winter Arc**
  (1 Oct – 31 Dec). The season can be set up in September and joined any
  day in season; a late join is "Day 15 of 92", never "Day 1".
- **Participation**: days before joining are neutral everywhere (streaks,
  Perfect/Minimum Days, XP, consistency, reflections, achievements,
  Insights) and show as dashed "Before you joined" markers on the Journey.
  Midwinter needs Day 46 to be a participated day; a late joiner who
  finishes the season still reaches the Summit.
- **Habit Setup v2**: a template catalogue, custom habits (done / not done,
  count, minutes, before a time) with random stable ids, edit and remove
  in setup, up to 12 habits.
- **Clock-time habits**: Sleep Before Target is a morning check-in ("Last
  night · 00:45 / Goal · before 01:00"), done when the bedtime is at or
  before the goal; the same goal on Minimum Days.
- Schema v5 (`arc_kind`, `participation_start_date`) with a tested v4 → v5
  and full-chain migration. Backup format 2; format-1 backups still
  restore.

**Phase 7:**
- Release audit and fixes; no new product scope (schema v5, backup format
  2).
- Branding: NextRep icon set (adaptive, themed, iOS, store), a night launch
  screen, and the "NextRep" name.
- The app moves to the new day at local midnight while open. An arc that
  ends at midnight opens its summary.
- Failure states with a way forward. A release-mode error panel. Labelled
  loading and intentional empty states.
- Accessibility:
  - screen-reader tap actions on every custom button
  - Journey days spoken in words, with 56 dp targets
  - 2× text fixes
  - celebrations wait for screen-reader users
- Release qualification on the emulator: notifications (deny, allow,
  deliver, background and cold-start taps, revoked) and the document
  picker (export, corrupted files, restore).
- Privacy, store readiness and metadata, release checklist, changelog. CI
  adds a release compile and a permission audit.

**Phase 8:**
- Qualification, not features (schema v5, backup format 2, no dependency
  change).
- The release build on the emulator:
  - in-place upgrades from schema v5 data and from a Phase 5 (schema v4)
    release
  - the core flow, notifications (deny, allow, delivery, background and
    cold-start taps, revocation)
  - document-picker backups (export, restore, corrupt copies refused)
  - 2× text and "Remove animations"
- Three P2 fixes found on the device:
  - the level row cut short at 2×
  - "1 reflections"
  - a doubled period in a spoken label
- Store screenshots from a synthetic backup tool.
- Physical Android, TalkBack, iPhone, VoiceOver, signing and owner
  decisions remain manual.

## Explicitly deferred

Custom seasons or lengths, adding or deleting habits in a running arc, a
Minimum Day policy for clock-time habits, merge-import, encrypted backups,
cloud sync, accounts, social, health integrations, AI, backend, payments,
cancelling or deleting an active arc. See
[docs/PHASE_6.md](docs/PHASE_6.md#phase-7-handoff).

## CI

[`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) runs on
every pull request and push to `main`:

- format check and analyze
- migration tests (v1 → v5) and backup format tests (v1 and v2)
- the release qualification tests, then all tests
- Android debug and release builds (the release build is debug-signed: no
  secrets in CI)
- a release permission audit that fails on `INTERNET`, exact-alarm or
  broad storage permissions

## Privacy

Local-only: no backend, analytics, telemetry, ads or trackers.

- **Reflections** are private text stored only in the on-device SQLite
  database. NextRep never uploads, logs or reports them (reflection storage
  errors keep only the error type, because SQLite errors can quote the
  values). The phone's own system backup (Android Backup, iCloud) may
  include app data when the user has it on; see [PRIVACY.md](PRIVACY.md).
  Notifications carry generic text only.
- **Reminders** are scheduled locally by the OS. There's no push service.
- **Backups** leave the device only when you export one, to the place you
  pick in the system file UI. They are checksummed (to detect damage), not
  encrypted. Backup errors never quote the file; restoring never turns
  reminders on.
- **Habit templates** are bundled in the app; custom habit ids are random
  and generated on the device.
- **Release APK permissions** (`aapt2 dump permissions`):
  - `POST_NOTIFICATIONS` and `VIBRATE` (notifications)
  - `RECEIVE_BOOT_COMPLETED` (restore reminders after a reboot)
  - AndroidX's app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
- No `INTERNET`, no exact-alarm permission and no storage permission
  (`MANAGE/READ/WRITE_EXTERNAL_STORAGE`): backups use the system document
  picker. `INTERNET` appears only in the debug/profile manifests, which
  Flutter tooling needs for hot reload.
