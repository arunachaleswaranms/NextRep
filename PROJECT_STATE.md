# PROJECT_STATE

_Last updated: 2026-10-05. Phase 6 complete on its branch, PR open, not
merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `7a0ac04` (squash merge of PR #5, Phase 5). PRs #1–#5
  are Phases 1–5.
- Working branch: `phase/6-seasonal-arc-and-habit-evolution`, from
  `7a0ac04`.
- PR: #6 (https://github.com/arunachaleswaranms/NextRep/pull/6), open for
  review, not merged.
- CI: Flutter CI run 37225305174 on the PR (`b449ab0`), both jobs green
  (format, analyze, migrations v1 → v5, backup format tests, all tests;
  Android debug build).
- Author and committer for all commits:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (set repo-locally).
  No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`
- Physical Android: CPH2707 (Android 16) over wireless ADB
- iOS: Xcode 27 beta, Swift Package Manager. Simulator iPhone 17 (iOS 27).
- Integration tests: always pass `--no-uninstall` (the default uninstall
  wipes the app's data on the device).
- Drift 2.35.1. Snapshots v1–v5 in `drift_schemas/` (v1–v4 unchanged).

## Architecture (current)

- Pure-Dart `domain/` owns truth. Drift `data/`, Riverpod controllers in
  `features/`, `app/` composition root, go_router.
- Arcs: `ArcKind` (`rolling92`, `seasonalWinter`) and
  `participationStartDate` are persisted. `WinterArcRules.problemWith`
  validates sessions. Seasonal rules live in `SeasonalWinterRules` and
  start rules in `ArcStartRules`.
- Participation lives on `WinterArcSession` (`isParticipatingOn`,
  `participatingDatesThrough`). `ArcHistory.elapsedDates` = participating
  dates, so pre-join days are neutral everywhere.
- Habits:
  - `HabitType.timeBefore` uses `NightTime` (1080–1799, 0 = not logged).
  - `HabitType.isCompletedBy` is the one completion rule.
  - Code-only `HabitTemplateCatalog`; `SetupHabitRules` covers custom
    habits, the 12-habit limit and duplicates.
  - Ids come from an injectable `HabitIdGenerator`.
- Backup: `BackupCodec` dispatches on version (format 1 frozen, format 2
  written). Other modules are unchanged from Phase 5.
- At most one unfinished arc. Derived, never stored: streaks, levels,
  Perfect Days, Journey, summaries, insights.

## Versions

- Database schema: **v5** (`arc_kind`, `participation_start_date`)
- Backup `formatVersion`: **2** (reads 1 and 2)
- App version: 1.0.0

## Dependencies added

None.

## Commands that passed (2026-10-04/05, final code)

- `dart format --set-exit-if-changed .`, `flutter analyze`: clean
- `dart run build_runner build --delete-conflicting-outputs`: v5 snapshot
  added
- `flutter test`: **566/566**. `flutter test --coverage`: **93.3%** of
  handwritten lib
- Migration tests (v1 → v5): 39/39. Backup tests (format 1 + 2): 70/70
- New suites: seasonal 22, participation 20, time-before 17, setup
  habits 16, backup v2 15, restore v2 10, v5 migration 11, Phase 6 flows 15
- `flutter test integration_test --no-uninstall`:
  - emulator-5554: 6/6
  - CPH2707: 6/6 (Phase 2 re-run after a wireless drop)
  - iPhone 17 simulator: 6/6
- `flutter build apk --debug` / `--release`, `flutter build ios
  --simulator`: pass
- `aapt2 dump permissions` (release): `RECEIVE_BOOT_COMPLETED`, `VIBRATE`,
  `POST_NOTIFICATIONS`, the app-private receiver permission.
  - Absent: INTERNET, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM,
    MANAGE/READ/WRITE_EXTERNAL_STORAGE.

## Device status

- Emulator (API 36, release): PASS, using the real in-season date with no
  clock change. Covered:
  - seasonal late join (Day 4), Habit Setup v2, templates, the custom form
  - Android time picker: pass, and daytime refused
  - Journey pre-join markers, trail and chapter count
  - persistence across reinstall and the date rollover
- Physical Android CPH2707: PASS.
  - Integration 6/6.
  - Release installed over the Phase 5 data: a real v4 → v5 migration,
    with the arc kept as rolling.
  - Left installed with its data.
- iOS: simulator build and integration 6/6. **PHYSICAL iOS — MANUAL
  REQUIRED** (no iPhone connected).

## Known debt

- Habits can't be added to or deleted from a running arc (needs a dated
  existence model).
- Clock-time habits: night window only, same target on Minimum Days, no
  bedtime analytics.
- A seasonal setup that outlives its season must be cancelled by hand.
- Unchanged from Phase 5:
  - backups are unencrypted (by design)
  - no merge-import
  - decoding runs on the UI isolate
  - reminders are inexact and pause after 14 idle days
  - Minimum Day is one-way
  - no past-day editing
  - close-out waits for an entry point

## Next recommended phase

**Phase 7:**
- active-arc habit creation with dated existence
- a clock-time Minimum Day policy and bedtime trends
- an iOS device pass and a screen-reader audit
- an optional encrypted backup as format 3
- Journey parallax and seasonal atmosphere

Details in `docs/PHASE_6.md#phase-7-handoff`.
