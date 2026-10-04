# Phase 3 — Winter Arc feel

## Goals

Phase 3 turns the working habit engine from Phase 1 and 2 into the Winter Arc
experience: "a cold journey toward a warm summit". It adds:

- a reusable, programmatic winter scene and a cinematic Today hero
- Journey v2, a mountain path over the existing 92-day history
- achievements, persisted unlocks and their celebrations
- the arc lifecycle: Day 92 close-out, a completed state and the
  End-of-Arc summary
- next-day habit edits (this closes the same-day Perfect Day loophole)
- schema v3, motion and haptics v2, accessibility and performance work
- GitHub Actions CI

The Phase 1/2 domain foundation is unchanged: `DayRules` is still the only
XP authority, and history (streaks, levels, Perfect Days, Journey states) is
still derived. Animation reacts to persisted results and never decides them.

```
user intent → domain validation → pure rules → transaction → persisted result
  → controller re-reads → UI → motion / haptics / celebration
```

## Product decisions (locked for this phase)

### Rolling 92-day arc

Unchanged: Day 1 is the local date when "Start Winter Arc" is pressed, and
Day 92 is Day 1 + 91 days. Sessions are not moved to a fixed Oct 1 → Dec 31
calendar, and no date migration was added. A seasonal preset could be a
separate product later.

### Habit edit timing

| Change | Takes effect |
|---|---|
| Title | immediately, everywhere (cosmetic) |
| Target, minimum target, enabled | from the **next challenge day** |

`HabitTrackingService.editHabit` stores a `habit_revisions` row with
`effective_from = today + 1`. Today's configuration is fixed once the day
starts, so an edit can't change today's completion, XP or Perfect Day.
Disabling or lowering an unfinished habit no longer makes today Perfect.

- Edits build on the configuration that will apply next. A second edit on the
  same day replaces that pending revision.
- Validation (ranges, "keep one habit enabled") is checked against the next
  day's configuration.
- **Day 92** has no next day. Configuration edits are rejected with
  `DomainRule.noNextChallengeDay`. Renames still work, and the editor
  disables the goal steppers and switches.
- Past configuration is never rewritten. Phase 2 revisions stored for their
  own day ("today" when they were made) stay valid history.
- The Habits screen shows today's goals and any pending change ("From
  tomorrow: 10 glasses · Minimum 3 glasses", "Off from tomorrow").

## Visual system

- **Tokens** (`app/theme/winter_tokens.dart`) are still the only place
  colours live:
  - Added scene tokens (sky, three mountain depths, snow, fog, two aurora
    tones, warm light, ember), glass surfaces and per-habit accents
    (`WinterHabitAccents`).
  - Journey "perfect" is now cyan. Warm amber is used for camp and summit
    light, and recovery orange for Minimum Day.
- **Surfaces**: translucent glass cards (no blur, so they're cheap to
  composite over the scene), a static night-sky and horizon background on
  every screen, and theme polish (navigation bar, app bar, type hierarchy).

## Winter Scene architecture

`lib/shared/winter_scene/`. It lives in `shared/` (not `features/`) because
Today, Journey, Summary and the background all use it.

| File | Role |
|---|---|
| `scene_progress.dart` | `SceneProgress`: pure mapping from challenge day (+ today's persisted result) to what the world shows |
| `scene_geometry.dart` | normalised shared layout (peaks, summit, camp, shelter, trail) so layers align at any size |
| `sky_layer.dart` | gradient, horizon glow (warmed by today's result), seeded stars |
| `aurora_layer.dart` | two soft curtains painted once; ambient drift is a transform and opacity, never a repaint |
| `mountain_layer.dart` | far range with summit and snowcaps, fog, middle ridge, near hills, pines |
| `cabin_layer.dart` | camp tents and fire, summit shelter, summit flag (`CampPainter`); the trail with its walked part lit (`TrailPainter`) |
| `snow_layer.dart` | capped snowfall (≤ 60 flakes, fewer on small areas), seamless loop |
| `winter_scene.dart` | `WinterScene`: composes the layers, owns the one ambient ticker |

Everything is drawn with `CustomPainter`, paths and gradients. There are no
image assets and nothing is downloaded at runtime. The scene is excluded from
semantics and hit testing, and it never carries information on its own.

### Scene milestones

From challenge-day position only (`ArcMilestone`, `domain/journey/arc_milestones.dart`):

| Day | Milestone | Scene |
|---|---|---|
| 1 | Frozen Trail | trail starts, summit deep in fog |
| 7 | First Camp | tent and campfire glow |
| 14 | Forest Camp | second tent, more pines |
| 30 | Mountain Ridge | ridge comes out of the fog |
| 45 | Aurora | restrained aurora (0.55) |
| 60 | High Ridge | rim-lit ridge, summit clearer |
| 75 | Summit Shelter | shelter window glows |
| 92 | Summit | fully revealed, flag and warm halo |

Today's result only changes the light. Warmth grows with completion and is
full on a Perfect Day, and a Minimum Day gives a recovery tint. Missed days
never hold the world back. Milestones are visual only and no business rule
reads them.

## Today v2

The top of Today is now a command centre (`TodayHero`):

- the live scene
- a milestone chip and a MINIMUM DAY / PERFECT DAY chip
- "Day X of 92" and the date
- a completion ring: cyan, recovery orange on a Minimum Day, gold when Perfect
- XP, level bar, Perfect streak and the next milestone

Everything comes from the persisted `DaySummary`. The hero computes nothing
the domain doesn't already provide.

Habit cards show:

- the habit's accent icon (a check badge when done)
- name and progress against today's effective target, with MINIMUM on a
  Minimum Day
- the streak
- a glow border instead of a heavy green fill
- clear − / + controls (or a check button); at the target the + rests as
  a "done" mark

Minimum Day keeps its warm recovery styling, with the copy "Keep moving, even
if today is smaller. / Consistency beats intensity."

## Journey v2

`features/journey/widgets/journey_path.dart` renders the unchanged
`JourneyDayState` model as a climb:

- A lazy `ListView.builder` with `reverse: true` and fixed per-kind extents
  (`itemExtentBuilder`). Day 1 is at the bottom, the summit at the top.
  Rows: base camp, the six chapter banners, 92 day rows, the summit.
- Chapters: Frozen Forest (1–14), First Ascent (15–30), Ridge (31–45), Aurora
  Pass (46–60), High Mountain (61–75), Summit Approach (76–92). They're visual
  only; the day number stays authoritative.
- Each row paints its own slice of one continuous trail (`pathX(y)`), so the
  trail is seamless while only visible rows are built. The walked part (up
  to today's marker) is lit cyan, the rest is dashed. Sparse scenery changes
  per chapter.
- It opens centred on today; a completed arc opens at the summit. Extents are
  fixed, so the offset is computed without building rows. The scroll position
  survives refreshes and tab switches.
- Behind the path is the scene at today's stage (no trail, dimmed). A
  compact header shows the day, chapter, milestone, Perfect stats, the
  level bar, a legend sheet and the trophy.

Day states never rely on colour alone:

| State | Shape | Fill | Icon | Size | Opacity |
|---|---|---|---|---|---|
| future | circle | none, dim outline | number | small | 0.55 |
| today | circle, 3 px snow ring + glow | blue tint | number | largest | 1 |
| perfect | circle + glow | full cyan | star | large | 1 |
| minimumComplete | rounded square + glow | full warm | fire | large | 1 |
| partial | circle | half cyan | number | medium | 1 |
| minimumPartial | rounded square | half warm | number | medium | 1 |
| missed | circle | none | dash | small | 0.7 |

Every marker is its own semantics node, e.g. "Day 12, Perfect" or
"Day 3, Today, today". Milestone flags ("Milestone First Camp, reached") light
up once reached. The day detail is read-only and keeps Day X, date, mode,
completed/total, %, XP, Perfect Day and per-habit progress, plus the chapter.
Future days can't be tapped.

## Achievements

### Catalog (`domain/achievement/achievement_catalog.dart`)

| Key | Title | Earned when | Earned on |
|---|---|---|---|
| `first_rep` | First Rep | any enabled habit completed | first such date |
| `first_perfect` | Clean Sweep | first Perfect Day | that date |
| `streak_3` | Snowball | any habit's run reaches 3 | date it reached 3 |
| `streak_7` | Cold Front | any habit's run reaches 7 | date it reached 7 |
| `perfect_3` | Three Perfect Days | 3 Perfect Days in total | the 3rd one |
| `minimum_complete` | Still Moving | a fully completed Minimum Day | first one |
| `level_2` | Getting Stronger | running XP ≥ 250 | first date it was |
| `level_3` | Momentum | running XP ≥ 500 | first date it was |
| `halfway` | Midwinter | challenge Day 46 reached | Day 46 |
| `summit` | Summit | the arc is over (today > Day 92) | Day 92 |

Keys are stable storage ids (`AchievementKey.id`). There are no secret
achievements. **Achievements never grant XP**, so the ledger keeps one
authority.

### Rule architecture

`AchievementRules.evaluate(ArcHistory)` is pure. It returns every currently
earned achievement and the challenge date it was first earned, in catalog
order. It uses only derived history: day records, streak marks
(`ArcHistory.habitMarks` and `StreakRules.firstReaching`, with the same
counting as streaks), the XP ledger by date (running total → `LevelRules`)
and the arc's dates. Nothing reads UI state. Past days are immutable, so a
past earned date never changes.

### Persistence (schema v3)

`achievement_unlocks`: `session_id` (FK, cascade), `achievement_key`,
`unlocked_on` (the challenge date it was earned), `unlocked_at` (when the
unlock was first stored). PK (`session_id`, `achievement_key`), so a key can
never be stored twice. The catalog stays in code. Unknown keys (from a future
version) are ignored on read.

Unlocks are permanent: undoing the habit that earned one doesn't remove it.

### Reconciliation

`AchievementService.reconcile()` is idempotent and serialised:

1. load `ArcHistory` (active or completed arc)
2. evaluate the rules
3. in one transaction: read stored keys, insert the missing ones
   (`INSERT OR IGNORE` as a second guard)
4. return exactly the newly stored unlocks

It never runs inside a habit action's transaction, and the UI wrapper
(`AchievementSync`) reports and swallows failures. A failed reconciliation
can't roll back or fail a habit action. It heals on the next run: after
each successful Today action, on Today load/refresh/resume (which also covers
app launch), on Journey load/refresh, on the Summary, and when the
Achievements screen opens.

### Unlock UI

- **Achievements screen** (`/achievements`, from the trophy button on Today
  and Journey, and from the Summary):
  - unlocked count and progress bar
  - a lazy two-column collection of hexagonal badges
  - locked badges are dark and outlined with a lock; unlocked ones glow and
    show "Day N · date"
  - each card has one semantic label, e.g. "Snowball. Locked. Reach a 3-day
    streak on any habit."
- **Celebrations**: one app-level `CelebrationQueue` and overlay (in
  `MaterialApp.router`'s builder) for Perfect Day / level-up and achievement
  cards.
  - Cards show one at a time and auto-dismiss after 3.2 s, or on a tap.
  - Waiting cards are ordered by priority (day events first).
  - Unlocks stored by one reconciliation share one card ("2 ACHIEVEMENTS
    UNLOCKED · First Rep · Clean Sweep"), so overlays never stack.
  - Only the run that stored an unlock queues it, so a celebration only
    ever follows a newly persisted unlock.

## Schema v3 and migration

`schemaVersion = 3`. The snapshots `drift_schema_v1.json`, `_v2.json` and
`_v3.json` are all committed, the v1/v2 ones unchanged. Frozen step helpers
are in `schema_versions.dart`, test schemas in `test/generated_migrations/`.

`_from2To3` only creates `achievement_unlocks`. There is no backfill: the
first launch after upgrading reconciles achievements from the existing
history. Session status `completed` already existed, so no completion flag
was added.

Migration tests:

- **v2 → v3** (`test/data/migration_v3_test.dart`):
  - an empty v2 database migrates to exactly the v3 snapshot
  - a realistic Phase 2 database migrates with everything kept: session,
    habit baseline, minimum targets, a same-day revision, a Minimum Day,
    progress, habit XP and Perfect Day bonuses
  - Today/Journey derive the same history, including the revision still in
    effect
  - reconciliation stores 5 unlocks with the right dates, a second run adds
    nothing, and XP is unchanged
  - Phase 3 writes work afterwards
- **v1 → v2 → v3** (`test/data/migration_test.dart`): the Phase 1 fixture
  now runs the whole chain and is validated against v3. All Phase 2
  assertions are kept, plus empty achievement storage and a 3-unlock
  reconciliation.
- **Device upgrade**: the Phase 2 release APK built from `main` (Perfect Day
  1, 90 XP, a minimum-target revision) was upgraded in place to the Phase 3
  release APK. Everything was intact, achievements reconciled to 2/10 on
  first launch, and the Achievements screen showed their real dates.

## Arc lifecycle

`ArcLifecycleService.reconcile()` (`domain/winter_arc/`):

- The arc stays `active` for the whole of Day 92. Day 92 is tracked
  normally.
- From the first local date after `endDate` it writes `completed`, once.
  Repeated and concurrent calls write nothing, it never closes early, and
  setup or completed sessions are left alone.
- No background job. It runs at deterministic entry points: launch
  (`bootLocationProvider`), resume and refresh of Today, and Journey loads.

A completed arc:

- tracking, Minimum Day and habit edits are rejected (`DomainRule.arcCompleted`)
- `DaySummary.isTrackable` and Habits editing are false
- Journey, achievements and the summary still load

**Routing fix**: `AppRoutes.forSession` sends a completed session to
`/summary` (Phase 2 sent it to Today, which needed an active session). The
`arcStatusProvider` notifier feeds a `refreshListenable`, and the router
redirects the active-arc tabs to `/summary` as soon as a close-out happens,
including on resume. `/summary/journey` (read-only Journey with a back
button) and `/achievements` stay reachable.

## End-of-Arc summary

`ArcSummary.fromHistory` (`domain/progress/arc_summary.dart`), entirely from
stored history:

- total XP and final level
- Perfect Days and best Perfect Day streak
- strongest habit: highest best streak, then most completed days, then
  display order (deterministic)
- habits completed (completed habit-days)
- Minimum Days completed
- achievements unlocked / total
- consistency = days with every habit done (Perfect + completed Minimum
  Days) ÷ elapsed days, rounded down

The screen shows the summit scene (warm, fully revealed, with the trail
drawing itself to the top), "WINTER ARC COMPLETE · 92 days" and the date
range, the strongest habit, a stat grid, "View Journey" and "Achievements".
There's no new-arc flow: the user isn't trapped (summary, Journey and
achievements are all reachable). Starting another arc is a Phase 4 decision.

## Motion v2

| Category | Token | Duration | Used for |
|---|---|---|---|
| micro | `WinterDurations.micro` | 150 ms | check transition |
| standard | `.standard` | 300 ms | progress, chips, markers, card glow, overlay fade |
| celebration | `.celebration` | 600 ms | hero warmth, level bar, badge reveal, milestone glow (summit reveal is 3×) |
| ambient | `.ambientLoop` | 24 s loop | snowfall, aurora drift |

`context.motion` returns zero durations, and `ambient == false`, when
`MediaQuery.disableAnimations` is on.

| Event | Motion | Haptic |
|---|---|---|
| habit complete | check scale/fade, progress bar | light |
| Perfect Day | ring completes in gold, hero warms, trail glow, card | medium + light |
| level up | level bar, compact level card | medium |
| achievement | badge scale-in card | light + medium |
| Minimum Day | warm recovery transition and banner | selection |
| Journey milestone | flag lights up once reached | — |
| arc complete | summit reveal | — |

Everything runs after `commitDay` (or a reconciliation) has persisted the
result.

## Accessibility

- The scene is decorative (`ExcludeSemantics`, `IgnorePointer`), so no
  information exists only in pictures.
- Journey markers are separate semantics containers with state labels.
  Shape, fill, icon, size and opacity encode state as well as colour. There's
  also a legend.
- Achievement cards: one label each, saying unlocked (with date) or locked.
  The trophy says "Achievements, N of 10 unlocked". Celebration cards are
  live regions with their own node and a "Tap to dismiss" hint.
- Text over the scene sits on a gradient scrim. Controls keep ≥ 48 dp
  targets, and Journey markers have a 56 dp target.
- Widget tests at 2× text (Today, Journey, Summary) find no overflow.
  Journey row heights grow with the text scale.
- Reduced motion: no ambient loop; transitions are immediate. Tested in
  widgets and smoke-tested on the emulator with Android's "remove
  animations" on.

## Performance

- One ambient ticker per visible scene. It stops in the background
  (`WidgetsBindingObserver`), on hidden tabs and covered routes
  (`TickerMode`, which go_router's indexed stack and the Navigator apply),
  under reduced motion, and when `ambientMotionProvider` is off. Tested.
- Every scene layer has its own `RepaintBoundary`. Only the snow layer
  repaints per frame (≤ 60 circles). The aurora animates by
  transform/opacity of a cached layer. Static painters repaint only when
  their inputs change (`shouldRepaint` on value-equal `SceneProgress`).
- Journey builds only visible rows: fixed extents, so it scrolls to today
  with no layout pass over 92 days. The summit card is a still picture with
  no ticker.
- The achievement collection is a lazy list of rows.
- There are a few more database reads per action (lifecycle check and
  achievement reconciliation each read the arc snapshot, at most ~650
  progress rows). They run after the UI has updated.

## CI

`.github/workflows/flutter-ci.yml`:

- Runs on `pull_request` and `push` to `main`, with `contents: read`, no
  secrets, nothing published.
- Pins Flutter 3.47.5.
- **quality** job: `pub get`, `dart format --output=none
  --set-exit-if-changed .`, `flutter analyze`, the migration tests on their
  own, then `flutter test`.
- **android** job: JDK 21, `flutter build apk --debug`.

## Test results (2026-10-04)

| Check | Result |
|---|---|
| `dart format .` | clean |
| `flutter analyze` | No issues |
| `flutter test` | 257 / 257 pass (Phase 2: 165) |
| `flutter test --coverage` | 93.2% of handwritten `lib/` (domain 96.6%, data 97.4%, features 95.4%, shared 94.6%) |
| migration tests (`migration_test.dart`, `migration_v3_test.dart`) | 18 / 18 pass |
| `flutter test integration_test -d emulator-5554` | 3 / 3 pass (Phase 1 Day 1, Phase 2 loop, new Phase 3 smoke) |
| `dart run build_runner build --delete-conflicting-outputs`, schema dump / steps / generate | done |
| `flutter build apk --debug` / `--release` | built |
| `aapt2 dump permissions` (release) | no `INTERNET` (only the app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`) |

New test files:

- `arc_milestones_test`, `achievement_rules_test`, `achievement_service_test`
- `habit_edit_timing_test`, `arc_lifecycle_test`, `arc_summary_test`
- `migration_v3_test`
- `features/winter_scene_test`, `features/phase3_flow_test`
- `integration_test/phase3_smoke_test`

Phase 1/2 tests were updated only for deliberate changes: next-day edits,
the reversed Journey scroll, the new edit copy, waiting for celebration
cards before tapping, and ambient motion off in UI tests. Their intent is
kept.

## Device validation

| Check | Result |
|---|---|
| Phase 2 → Phase 3 upgrade (release over release) | PASS: data intact, 2 achievements reconciled with dates |
| Today opens, hero renders | PASS |
| Habit completion, Perfect Day (undo / redo, card, +30 once) | PASS |
| Minimum Day (sheet, warm state, completion → "Still Moving") | PASS |
| Journey v2 renders all 92 days; detail works | PASS (integration test scrolls to Day 92) |
| Achievement unlocks once, persists after restart, screen reflects it | PASS |
| Level / streak correct | PASS |
| Habit edit saved and shown as "From tomorrow" | PASS (the next-day effect itself is covered by clock-injected tests) |
| Force-stop / relaunch, background / foreground | PASS |
| Reduced motion (Android "remove animations") | PASS (smoke) |
| Arc close-out on Day 93 | Clock-injected tests only (no device date changes) |
| Physical Android | **MANUAL REQUIRED**: no device connected |
| iOS | **DEFERRED**: CocoaPods not installed. The toolchain was not changed |

## Limitations

- Unlocks are permanent; undoing the action that earned one doesn't revoke it.
- Arc close-out happens at the next entry point (launch, resume, refresh). An
  app left open in the foreground across midnight after Day 92 shows the
  non-trackable "Winter Arc complete" Today until any of those happen.
- No new-arc flow after completion. No past-day editing, habit creation or
  deletion.
- Minimum Day is still one-way. "Sleep Before Target" is still binary.
- Haptics and the visual look were checked on the emulator only, not
  asserted in tests. No physical-device pass yet.
- Scene art is programmatic and intentionally restrained. There's no
  parallax yet.

## Phase 4 handoff

1. Physical Android pass (snow/aurora smoothness, haptics, TalkBack) and the
   iOS toolchain.
2. What happens after an arc: start a new arc, history of past arcs, or a
   seasonal preset.
3. Retention without pressure: an optional evening check-in, local
   notifications (opt-in), a reflection/journal.
4. Achievements v2 (more catalog entries, possibly secret ones). Decide
   whether unlocks should ever be revocable.
5. Scene v2: parallax on Journey, per-chapter art, optional sound.
6. Consider a habit "threshold" type for Sleep Before Target, and habit
   creation.
