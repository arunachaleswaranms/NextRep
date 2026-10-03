# PROJECT_STATE

_Last updated: 2026-10-03. Phase 2 complete on its branch, PR open, not merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main`: `10d8185` (merge of PR #1, Phase 1)
- Working branch: `phase/2-habit-loop-depth`, branched from `10d8185`. HEAD
  is the `docs:` commit at the top of `git log --oneline origin/main..HEAD`.
- Author and committer for all commits:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (set repo-locally).
  No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
  (the system default is JDK 25)
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`
- Drift 2.35.1. Schema snapshots in `drift_schemas/`, versioned migration
  helpers in `lib/core/database/schema_versions.dart`, test schemas in
  `test/generated_migrations/`

## Architecture (current)

- Pure-Dart `domain/` owns truth. Drift `data/`, Riverpod controllers in
  `features/`, `app/` composition root, go_router.
- One write path for the current day: `ProgressRepository.commitDay` (a
  transaction) + `DayRules.settle` (pure). The XP ledger for a date is a
  function of that date's state: +15 per completed enabled habit, +30 per
  Perfect Day.
- History-safe config: baseline in `habits` + dated `habit_revisions` (only
  ever written for today) + `day_modes`. Streaks, levels, Perfect Days and
  Journey states are derived (`ArcHistory`, `LevelRules`).
- `StatefulShellRoute` with Today and Journey tabs. Onboarding, setup and the
  habit editor sit outside the tabs.
- Schema v2. The v1 → v2 migration is additive and backfills minimum
  targets and Perfect Day bonuses.

## Commands that passed (2026-10-03)

- `dart format .` (clean), `flutter analyze` (no issues)
- `dart run build_runner build --delete-conflicting-outputs`, schema dump /
  steps / generate
- `flutter test`: 165/165. `flutter test --coverage`: 90.5% handwritten lib
  (domain 96.6%, data 97.1%, features 94.5%)
- `flutter test test/data/migration_test.dart`: 10/10 (v2 schema validated)
- `flutter test integration_test -d emulator-5554`: 2/2
- `flutter build apk --debug` and `--release`: pass. `aapt2 dump permissions`
  on release: no INTERNET.

## Emulator / manual status

- **Upgrade path: PASS.** Phase 1 release APK (built from `main`), Day 1
  perfect (60 XP) → installed the Phase 2 release APK over it → app opens in
  the tab shell with all data intact. The backfilled bonus gives 90 XP and
  the PERFECT DAY badge shows.
- **Phase 2 flow: PASS** (same device, release build):
  - Undo the final habit → 45 XP, "Perfect Day bonus removed".
  - Redo → celebration, 90 XP once. Level bar 90/250.
  - Undo → "Having a rough day?" → sheet → Minimum Day: targets 10 min / 3
    glasses / 5 min, progress kept, XP unchanged.
  - Force-stop/relaunch → Minimum Day persists.
  - Edit water to 10 normal / 2 minimum → persists across relaunch.
  - Complete → Journey shows Day 1 "Minimum complete". Detail sheet values
    correct.
  - Today ↔ Journey switching works. Final force-stop/relaunch → Today intact.
- Physical Android device: **MANUAL REQUIRED** (not tested).
- iOS: not attempted (CocoaPods missing).

## Known debt

- Habit edits apply to today, so disabling an unfinished habit can make today
  Perfect. Documented, and needs a product call.
- No arc close-out after Day 92. `completed` status is still unused.
- No habit creation/deletion. No past-day editing (by design).
- "Sleep Before Target" is binary pending a threshold habit type.
- Error reporting is local `dart:developer` logging only.

## Open product decisions

- **Season dates:** the arc is still start-date based (Day 1 = start press,
  end = Day 1 + 91). Should Winter Arc be fixed to Oct 1 → Dec 31? Unresolved.
  Not changed in Phase 2.
- Should habit edits take effect today or tomorrow?
- Should Minimum Day be reversible (currently one-way)?
- Is the Perfect Day bonus backfill for pre-v2 days wanted? (It is applied.)

## Next recommended phase

**Phase 3: Winter Arc feel.** Cinematic Journey v2 on the existing day
states, winter scene layer (reduced-motion aware), achievements from
`ArcHistory`, arc close-out, and the open product decisions above. Details in
`docs/PHASE_2.md#phase-3-handoff`.
