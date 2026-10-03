# PROJECT_STATE

_Last updated: 2026-10-02. Phase 1 complete, PR open, not merged._

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main`: `66eafd3` (Flutter scaffold only)
- Working branch: `phase/1-foundation-day1`. HEAD is the `docs:` commit on top
  of `19bbd85` (`git log --oneline -7`).
- Author for all commits: `Arunachaleswaran M S <arunachaleswaranms@gmail.com>`
  (set repo-locally). No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on PATH;
  use `export PATH="$HOME/development/flutter/bin:$PATH"`)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
  (the system default is JDK 25)
- Emulator: AVD `RideLink_API36` (API 36, arm64) → `emulator-5554`

## Completed (Phase 1)

- Architecture: pure-Dart `domain/`, Drift `data/`, Riverpod `features/`,
  `app/` composition root, go_router, theme tokens
- SQLite schema v1 (sessions, habits, daily progress, XP ledger) + snapshot
- Onboarding → Habit Setup → Start → Today. Boot routing from DB state
- Binary complete/undo, count/duration steppers, completion %, XP total
- Idempotent XP (+15 per habit-day, revoked on undo), serialized actions,
  stale-day guard, refresh on resume, error model with user messages

## Commands that passed (2026-10-02)

- `dart format .` (clean), `flutter analyze` (no issues)
- `flutter test`: 65/65. `flutter test --coverage`: 86% handwritten lib
- `flutter test integration_test -d emulator-5554`: pass
- `flutter build apk --debug`: pass
- `flutter build apk --release`: pass. `aapt2 dump permissions` shows no INTERNET
- Manual adb smoke on emulator: onboarding → setup (selection kept across
  force-stop) → start → Today → double tap complete (15 XP once) → 20% →
  force-stop → cold relaunch → Today with state intact: **PASS**

## Outstanding / manual

- iOS build/run not attempted (CocoaPods missing on this machine)
- Physical Android device not tested (emulator only)
- PR review and merge to `main` is the owner's call

## Known debt

- Arc dates follow the start date (Oct 2 start → Jan 1 end). Confirm whether
  the season should be fixed to Oct 1 → Dec 31.
- No habit editing after start, no past-day edits, no arc close-out after Day 92
- "Sleep Before Target" is binary pending a threshold habit type
- Error reporting is local `dart:developer` logging only

## Next recommended phase

**Phase 2: Habit loop depth.** Streaks and perfect days → levels from the XP
ledger → Minimum Day mode → habit editing → bottom-nav shell with a Journey
grid → schema v2 migration with migration tests. Details in
`docs/PHASE_1.md#phase-2-handoff`.
