# PROJECT_STATE

_Last updated: 2026-10-04. Phase 4 complete on its branch, PR open, not
merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `83680ab` (squash merge of PR #3, Phase 3). PR #1 is
  Phase 1, PR #2 Phase 2.
- Working branch: `phase/4-retention-and-arc-history`, from `83680ab`.
- PR: _pending_. CI: _pending_.
- Author and committer for all commits:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (set repo-locally).
  No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`
- iOS: Xcode 27 beta; CocoaPods **not** installed, and not needed
  (Swift Package Manager). Simulator iPhone 17 (iOS 27).
- Drift 2.35.1. Snapshots v1–v4 in `drift_schemas/`, frozen steps in
  `lib/core/database/schema_versions.dart`, test schemas in
  `test/generated_migrations/`
- CI: `.github/workflows/flutter-ci.yml` (Flutter 3.47.5, JDK 21)

## Architecture (current)

- Pure-Dart `domain/` owns truth. Drift `data/`, Riverpod controllers in
  `features/`, `app/` composition root, go_router.
- Sessions: any number completed, at most one unfinished (setup/active).
  This is enforced by the service, the create transaction and the
  `single_open_session` index.
- `CurrentArcService` resolves arcs explicitly. Writes go only to the
  active arc, with the shown session id checked. History views take
  `/arc/:sessionId` and are read-only.
- One write path for the current day: `ProgressRepository.commitDay` +
  `DayRules.settle`, the only XP authority.
- Journal: `daily_reflections`, one per session and date; only today of
  the active arc is writable.
- Reminders: `ReminderService.reconcile` → pure `ReminderPlanner` →
  `ReminderScheduler` (`flutter_local_notifications`). Inexact one-shots
  for 14 days, only while an arc is active.
- Achievements: 15 keys; `AchievementRules.evaluate(AchievementContext)`
  is pure; idempotent reconcile of the home arc; no XP.
- Derived, never stored: streaks, levels, Perfect Days, Journey states,
  summaries, history cards.
- Schema v4.

## Package additions (Phase 4)

`flutter_local_notifications ^22.3.1`, `timezone ^0.11.1`, `characters
^1.4.0` (was transitive). Android: core library desugaring
(`desugar_jdk_libs 2.1.4`).

## Commands that passed (2026-10-04)

- `dart format .` (clean), `flutter analyze` (no issues)
- `dart run build_runner build --delete-conflicting-outputs`, schema dump /
  steps / generate (v4)
- `flutter test`: 348/348. `flutter test --coverage`: 93.0% handwritten lib
- Migration tests (`migration_test`, `migration_v3_test`,
  `migration_v4_test`): 28/28
- `flutter test integration_test`: emulator-5554 4/4; iOS simulator 4/4
- `flutter build apk --debug` and `--release`; `flutter build ios
  --simulator`: pass
- `aapt2 dump permissions` on release:
  - `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED` (plus the
    existing AndroidX dynamic-receiver permission)
  - no INTERNET, no SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM

## Device status

- Emulator (API 36): PASS.
  - Phase 3 → 4 upgrade with data intact.
  - Notification permission prompt, delivery (background and killed
    process), tap → Today / Journal including cold launch.
  - Disable → 0 alarms; denial path; release-build delivery; Journal
    keyboard.
- Physical Android: **MANUAL REQUIRED** (none connected).
- iOS: simulator build and integration tests PASS; iOS notification
  delivery not checked.

## Known debt

- Reminders pause after 14 days without opening the app; delivery is
  inexact.
- No export/backup; no deleting arcs; a setup arc can't be cancelled.
- Unlocks are permanent. Minimum Day is one-way. No habit
  creation/deletion or past-day editing.
- Close-out still waits for an entry point (launch / resume / refresh).
- Error reporting is local `dart:developer` logging only.

## Next recommended phase

**Phase 5: data safety and insight.** Physical-device pass (Android and
iOS notifications), local export/backup of arcs and the Journal, then
cancel-setup / delete-arc on top of it, an optional seasonal (1 Oct →
31 Dec) preset, on-device cross-arc and mood insights, and Journey scene
v2 (parallax). Details in `docs/PHASE_4.md#phase-5-handoff`.
