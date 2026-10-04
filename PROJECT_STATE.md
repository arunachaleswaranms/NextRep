# PROJECT_STATE

_Last updated: 2026-10-04. Phase 3 complete on its branch, PR open, not
merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main`: `789da07` (squash merge of PR #2, Phase 2). Phase 1 is PR #1.
- Working branch: `phase/3-winter-arc-feel`, branched from `789da07`.
- Author and committer for all commits:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (set repo-locally).
  No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`
- Drift 2.35.1. Snapshots v1–v3 in `drift_schemas/`, frozen steps in
  `lib/core/database/schema_versions.dart`, test schemas in
  `test/generated_migrations/`
- CI: `.github/workflows/flutter-ci.yml` (Flutter 3.47.5, JDK 21)

## Architecture (current)

- Pure-Dart `domain/` owns truth. Drift `data/`, Riverpod controllers in
  `features/`, `app/` composition root, go_router. The reusable scene is in
  `shared/winter_scene/`.
- One write path for the current day: `ProgressRepository.commitDay` +
  `DayRules.settle`, which is the only XP authority.
- Habit edits: renames now; target / minimum / enabled as a revision
  effective tomorrow. On Day 92 config edits are rejected.
- Derived, never stored: streaks, levels, Perfect Days, Journey states,
  scene milestones, the summary.
- Achievements: rules derived from `ArcHistory`, unlocks persisted in
  `achievement_unlocks` by an idempotent reconcile, run best effort outside
  habit transactions. No XP.
- Lifecycle: `ArcLifecycleService` marks the arc `completed` after Day 92,
  at launch, resume and Today / Journey refresh. A completed arc is
  read-only, and `/summary` is its home (router redirect).
- Schema v3.

## Commands that passed (2026-10-04)

- `dart format .` (clean), `flutter analyze` (no issues)
- `dart run build_runner build --delete-conflicting-outputs`, schema dump /
  steps / generate
- `flutter test`: 257/257. `flutter test --coverage`: 93.2% handwritten lib
- Migration tests (`migration_test.dart` + `migration_v3_test.dart`): 18/18
- `flutter test integration_test -d emulator-5554`: 3/3
- `flutter build apk --debug` and `--release`: pass. `aapt2 dump permissions`
  on release: no INTERNET.

## Emulator / manual status

- Phase 2 release → Phase 3 release upgrade: PASS. Data intact, 2
  achievements reconciled with their dates.
- Today hero, habit completion, Perfect Day undo/redo, Minimum Day (→
  "Still Moving"), habit edit "From tomorrow", Journey v2, Achievements,
  force-stop/relaunch, background/foreground, reduced motion: PASS.
- Arc close-out: clock-injected tests only.
- Physical Android device: **MANUAL REQUIRED** (none connected).
- iOS: **DEFERRED** (CocoaPods missing).

## Known debt

- Unlocks are permanent (undo doesn't revoke). No new arc after
  completion.
- Close-out waits for the next entry point (launch / resume / refresh).
- Minimum Day is one-way. "Sleep Before Target" is binary. No habit
  creation/deletion or past-day editing.
- Error reporting is local `dart:developer` logging only.

## Open product decisions

- What happens after the summit: a new arc, arc history, or a seasonal
  preset?
- Should achievement unlocks ever be revocable?
- Should Minimum Day be reversible?

## Next recommended phase

**Phase 4: life after the summit and gentle retention.** Physical-device and
iOS pass, a new-arc flow / arc history, opt-in local reminders, an evening
check-in or journal, achievements v2, Journey parallax. Details in
`docs/PHASE_3.md#phase-4-handoff`.
