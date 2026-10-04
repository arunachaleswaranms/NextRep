# PROJECT_STATE

_Last updated: 2026-10-04. Phase 5 complete on its branch; PR pending
review, not merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `970d27b` (squash merge of PR #4, Phase 4). PRs #1–#4
  are Phases 1–4.
- Working branch: `phase/5-data-safety-and-insight`, from `970d27b`.
- PR: pending (see below).
- CI: pending (see below).
- Author and committer for all commits:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (set repo-locally).
  No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`
- Physical Android: CPH2707 (Android 16) over wireless ADB
- iOS: Xcode 27 beta, Swift Package Manager (CocoaPods not installed, not
  needed). Simulator iPhone 17 (iOS 27).
- Integration tests: always pass `--no-uninstall`. The default uninstalls
  the app afterwards, which wipes its data on the device.
- Drift 2.35.1. Snapshots v1–v4 in `drift_schemas/` (unchanged in Phase 5)

## Architecture (current)

- Pure-Dart `domain/` owns truth. Drift `data/`, Riverpod controllers in
  `features/`, `app/` composition root, go_router.
- Sessions: any number completed, at most one unfinished (service, create
  transaction, `single_open_session` index).
- Backup: `domain/backup/` holds the format and service.
  - `BackupCodec`: canonical JSON + SHA-256.
  - `BackupValidator` → `ValidatedBackup`, the only input restore takes.
  - `BackupService`: export, inspect, restore.
  - `DriftBackupStore`: one-transaction replace, verified before commit.
  - Restored arc ids are shifted past every id the database has used.
  - Reminders restore off.
- After a restore: `AppEpoch.restart()` re-runs the boot location and
  rebuilds the router. Every repository provider watches the epoch, so all
  services and controllers reload.
- Deletion: `WinterArcService.deleteCompletedArc` (completed only) and
  `cancelSetup` (setup only); the status is re-checked in the delete
  transaction; FK cascades; no orphan rows left.
- Insights: `InsightService` reads facts (moods without text); pure
  `InsightRules`; never persisted.
- Derived, never stored: streaks, levels, Perfect Days, Journey,
  summaries, history cards, insights.

## Versions

- Database schema: **v4** (no Phase 5 migration needed)
- Backup `formatVersion`: **1** (independent of the schema)
- App version: 1.0.0 (`lib/app/app_info.dart`, test-checked against
  pubspec)

## Package additions (Phase 5)

`file_picker ^13.1.0` (SAF / UIDocumentPicker, no storage permission, SPM),
`crypto ^3.0.7` (SHA-256).

## Commands that passed (2026-10-04)

- `dart format --set-exit-if-changed .`, `flutter analyze`: clean
- `flutter test`: **440/440**. `flutter test --coverage`: **93.7%** of
  handwritten lib
- Migration tests (v1/v2/v3 → v4): 28/28
- Phase 5 suites (backup format, restore, deletion, insights, flows,
  routes): 92/92
- `flutter test integration_test --no-uninstall`:
  - emulator-5554: 5/5
  - CPH2707: 5/5
  - iPhone 17 simulator: 5/5
- `flutter build apk --debug` / `--release`, `flutter build ios
  --simulator`: pass
- `aapt2 dump permissions` (release): `RECEIVE_BOOT_COMPLETED`, `VIBRATE`,
  `POST_NOTIFICATIONS`, the app-private receiver permission.
  - Absent: INTERNET, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM,
    MANAGE/READ/WRITE_EXTERNAL_STORAGE.

## Device status

- Emulator (API 36, release): PASS. Covered:
  - restore through DocumentsUI on a fresh install
  - export through the Save dialog (re-export identical)
  - replace with the second confirmation
  - corrupt file refused
  - relaunch persistence, delete arc, cancel setup
  - logcat privacy
- Physical Android CPH2707: PASS. Covered:
  - integration tests 5/5
  - picker restore and export
  - reminders on/off (inexact, all cancelled)
  - delete arc, background/resume
  - The app was left installed with test data and reminders off; the
    test files were removed.
- iOS: simulator build and integration 5/5. The iOS document picker is
  **MANUAL REQUIRED**. No iPhone connected.

## Known debt

- Backups aren't encrypted (by design, documented); no merge-import.
- Export refuses data dated after "now" (a clock moved backwards).
- Backup decoding runs on the UI isolate (fine for real KB-sized backups).
- Reminders pause after 14 days without opening the app; delivery is
  inexact.
- Minimum Day one-way; no habit creation; no past-day editing; close-out
  waits for an entry point.

## Next recommended phase

**Phase 6:**
- Seasonal Winter Arc preset (needs a product design first)
- iOS device pass (document picker, notifications) and TalkBack
- optional encrypted backup (format 2)
- custom habits during setup and a time-based sleep habit
- restrained Journey parallax

Details in `docs/PHASE_5.md#phase-6-handoff`.
