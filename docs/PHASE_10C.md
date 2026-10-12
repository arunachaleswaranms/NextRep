# Phase 10C: New Habit Templates & Expanded Achievements

## Objective

Toward v1.1.0 (not released by this phase):

1. Six optional built-in habit templates.
2. The achievement catalog grows from 15 to **32**, including achievements
   tied to specific built-in activities.
3. The collection is grouped into six categories.
4. Achievements a newer catalog adds are **backfilled** from history that
   is already stored, safely and idempotently.

Not in scope: water reminders, social-media monitoring, adding a habit to
a running Arc, achievement XP, schema or backup format changes.

## Baseline

| | |
|---|---|
| `main` | `5cb6d90759fac8a87ff73d4f1956acbe6fffff0b` (squash merge of PR #12, Phase 10B) |
| Releases | `v1.0.0` is the only tag and GitHub Release |
| v1.1.0 | no tag, no release |
| Branch | `phase/10c-habits-achievements` |

## 1. Habit templates

Six templates are added to `HabitTemplateCatalog`, after the Phase 6 set.
None of them is a starter (`starter: false`) or switched on by default
(`enabledByDefault: false`), so a fresh setup is seeded exactly as before.

| id | Title | Type | Target | Minimum | Icon (Material) |
|---|---|---|---|---|---|
| `hair_care` | Hair Care | done / not done | 1 | 1 | `content_cut_rounded` |
| `skin_care` | Skin Care | done / not done | 1 | 1 | `face_retouching_natural_rounded` |
| `fruit` | Eat Fruit | done / not done | 1 | 1 | `eco_rounded` |
| `nuts_seeds` | Nuts / Seeds | done / not done | 1 | 1 | `grain_rounded` |
| `mobility` | Stretch / Mobility | minutes | 10 min | 5 min | `accessibility_new_rounded` |
| `reading` | Reading | minutes | 15 min | 5 min | `auto_stories_rounded` |

Descriptions are neutral. There are no medical, treatment, nutrition or
quantity claims, and nothing about any particular product.

- **Ids are stable forever.** Each template's `iconKey` equals its id.
- **Presentation:** each key has its own glyph in `HabitIcon` and its own
  accent in `WinterHabitAccents` (the token map that already holds habit
  accents). The keys are also in `HabitIconKeys`, so they can be picked for
  a custom habit. Unknown keys still fall back to the generic check icon
  and the primary accent.
- **One path:** Add Habit → template picker → `WinterArcService.addTemplateHabit`
  → `SetupHabitRules.fromTemplate` → an ordinary persisted `Habit`. No UI
  special case. The habit is added switched on. A duplicate is rejected
  (`duplicateHabit`), and the 12-habit limit applies (`habitLimitReached`).

### Setup only: no habit is added to a running Arc

After an Arc starts, its habits can be renamed, re-targeted from the next
day, or switched off and on. They can't be added or deleted: a new habit
in the middle of an Arc would need dated "exists from" semantics so that
it doesn't appear retroactively on earlier days. That is a separate
architecture decision, and **this phase does not make it.**

So the new templates are offered while an Arc is in **setup**: a first
Arc, a future Arc, or before pressing Start. `addTemplateHabit` already
requires setup, and a test proves a running Arc rejects it and gains no
habit. `Habit.createdAt` is not reinterpreted, there is no hidden schema
workaround, and existing Arcs (including the legacy `sleep_on_time` habit)
are untouched. Reuse Last Setup is unchanged.

## 2. Achievement catalog: 15 → 32

All 15 existing `AchievementKey` ids are unchanged. 17 values are appended
(the enum order is `values` order; the stored id is the contract):

| Key | Stored id | Title | Criterion | Category |
|---|---|---|---|---|
| `streak14` | `streak_14` | Two Weeks Strong | a 14-day streak on any habit | Consistency |
| `streak30` | `streak_30` | Cold Discipline | a 30-day streak on any habit | Consistency |
| `streak50` | `streak_50` | Iron Winter | a 50-day streak on any habit | Consistency |
| `perfect25` | `perfect_25` | Quarter Century | 25 Perfect Days in total | Consistency |
| `minimum7` | `minimum_7` | Bend, Don't Break | 7 fully completed Minimum Days | Resilience |
| `reflections14` | `reflections_14` | Two Weeks Inward | reflections on 14 days | Reflection |
| `reflections30` | `reflections_30` | Know Yourself | reflections on 30 days | Reflection |
| `day14` | `day_14` | First Chapter | Day 14 of the Arc | Journey |
| `day60` | `day_60` | Aurora | Day 60 of the Arc | Journey |
| `day75` | `day_75` | Final Approach | Day 75 of the Arc | Journey |
| `noJunk7` | `no_junk_7` | Clean Week | a 7-day No Junk Food streak | Habit Mastery |
| `noJunk30` | `no_junk_30` | Intentional Month | a 30-day No Junk Food streak | Habit Mastery |
| `noJunk50` | `no_junk_50` | Deep Discipline | a 50-day No Junk Food streak | Habit Mastery |
| `workout30` | `workout_30` | Built by Reps | the Workout goal met on 30 days | Habit Mastery |
| `water30` | `water_30` | Hydration Rhythm | your own Water Intake goal met on 30 days | Habit Mastery |
| `learning30` | `learning_30` | Always Learning | the Learning / Skills goal met on 30 days | Habit Mastery |
| `sleep14` | `sleep_before_14` | Rest Rhythm | Sleep Before Target met on 14 days | Habit Mastery |

Achievements are still collectibles only and grant **0 XP**. The ledger
has one authority (`DayRules`).

### Categories

`AchievementCategory` is display metadata on `AchievementDefinition`. It
is **never persisted**. The catalog is now in category order. That order
is presentation only, and a celebration lists unlocks in that order.

| Category | Count | Achievements |
|---|---|---|
| Progress | 4 | First Rep, Getting Stronger, Momentum, Stronger Every Day |
| Consistency | 9 | Clean Sweep, Snowball, Cold Front, Two Weeks Strong, Cold Discipline, Iron Winter, Three Perfect Days, Ten Clean Sweeps, Quarter Century |
| Resilience | 3 | Still Moving, Adaptable, Bend, Don't Break |
| Habit Mastery | 7 | Clean Week, Intentional Month, Deep Discipline, Built by Reps, Hydration Rhythm, Always Learning, Rest Rhythm |
| Reflection | 4 | Looking Inward, Seven Check-ins, Two Weeks Inward, Know Yourself |
| Journey | 5 | First Chapter, Midwinter, Aurora, Final Approach, Summit |
| **Total** | **32** | |

### Badges

`AchievementVisuals` keeps exhaustive switches, so every new key has a
deliberately chosen glyph and accent from the existing winter palette. The
32 glyphs are all different. Accents by theme: snow / aurora for streaks,
celebration for Perfect Days, recovery for Minimum Days, aurora violet for
reflections and rest, aurora green / warm light for the journey, and
aurora green for No Junk Food. The unlock animation, celebration card and
Phase 10B share card work for the new keys with no special casing.

## 3. Rules

`AchievementRules` stays pure, deterministic and database-free. It reads
only the `AchievementContext`: the `ArcHistory` and the dates that have a
reflection. Shared helpers replace per-achievement loops:

- `_firstHabitStreak(history, length)`: the earliest date any habit's run
  reached `length`. Used by Snowball, Cold Front and the 14 / 30 / 50
  streaks.
- `_firstStreakOf(history, habitId, length)`: the same for one habit
  (`StreakRules.firstReaching` over `ArcHistory.habitMarks`). Used by the
  No Junk Food runs.
- `_nthCompletedDay(history, habitId, n)`: the nth elapsed date whose
  `DayRecord.entryFor(habitId)` is complete. Used by Workout, Water,
  Learning and Sleep.
- `_participatedMilestone(history, dayNumber)`: challenge day `dayNumber`
  itself, once it has started and only if the user took part that day.
  Used by Day 14, Midwinter (refactored onto it), Day 60 and Day 75.
- `_nth(dates, n)`: Perfect, Minimum and reflection totals.

### Generic achievements

- **Streaks** use the same semantics as Snowball and Cold Front: a day the
  habit was disabled is skipped, a completed Minimum Day counts, a miss
  resets the run, and today counts only once it is completed.
- **Quarter Century** is the 25th Perfect Day. A Minimum Day is never a
  Perfect Day.
- **Bend, Don't Break** is the 7th fully completed Minimum Day. It's a
  resilience award: using Minimum Days is never penalised.
- **Reflections** use only the *dates* that have a saved reflection,
  de-duplicated and limited to the Arc's elapsed participating days. The
  rules never see win or improvement text or the mood.
- **Journey milestones** are earned on the day itself and only if the user
  took part that day. A season joined on Day 15 never earns Day 14; one
  joined before Day 60 earns Day 60 when it arrives. A milestone is never
  earned early.

### Activity-specific achievements: stable ids, never titles

They key off the built-in habit's stable id: `no_junk_food`, `workout`,
`water`, `learning` and `sleep_before`. They never look at the title, icon
or position. So:

- a renamed built-in habit still qualifies;
- a custom habit with the same name (`custom_<hex>` id) never does;
- the legacy `sleep_on_time` habit (a different type and id) never counts
  toward Rest Rhythm.

For the totals, each elapsed participating date is examined:
`record.entryFor(id)`. If there is no entry, the habit wasn't enabled that
day: not applicable, skipped. If `entry.progress.completed`, the day
counts. The nth such date is the earned date. Days are cumulative, not
necessarily consecutive. `DayRecord` / `DayRules` stays the authority on
completion, so these follow automatically:

- **Goal changes:** completion is against the target in effect that day.
- **Minimum Days:** meeting the minimum target is a legitimate completion
  and counts.
- **Water** is "your own goal": there is no fixed number of glasses
  anywhere in the rules.
- **Sleep Before** uses the Phase 6 semantics (date D is the bedtime of
  the sleep that ended on the morning of D) through the entry's completion.
  The rule never reads the logged clock time.

The No Junk Food runs use the normal habit streak engine; there is no
second streak definition.

## 4. Backfill

A v1.0 install has already stored unlocks for the 15 old achievements. Its
history may already qualify for new ones: for example 34 Workout days, a
31-day No Junk Food run, Day 64 reached and 18 reflections. v1.1 derives
those unlocks from that history. The user doesn't have to earn them again.

### Algorithm: `AchievementService.backfillCatalog()`

1. Resolve the home Arc: the active Arc or, with nothing unfinished, the
   latest completed Arc.
2. For every started session (`listSessions()`, skipping `setup`), other
   than the home Arc: evaluate the full catalog against its stored history
   and reconcile its unlocks. These Arcs are completed history: every one
   of their days is before today, so they can only gain unlocks, never
   lose one.
3. Reconcile the home Arc exactly as `sync()` does.
4. Return `CatalogBackfill(home: UnlockChanges, historical: {sessionId: [unlocks]})`.

It uses the existing `AchievementRepository.reconcileUnlocks`, unchanged:

- each new unlock's **`unlockedOn` is the historical date** it was first
  earned, not the upgrade day. `unlockedAt` is when the row was persisted;
- an existing unlock is never rewritten (the first unlock wins);
- rows with **unknown keys** are never touched, and nothing of another
  session is ever read or written;
- running it again changes nothing. There is no migration flag and no
  stored counter.

### Celebration

`AchievementSync` (the UI's best-effort runner) does a catalog backfill on
its **first successful run of each app session**, and again after a
restore, because the provider is rebuilt on the app epoch. Later runs
reconcile the home Arc only. The app also starts one run at launch, so
completed Arcs are backfilled even when the first screen isn't Today (for
example while a new Arc is in setup).

- The home Arc's new unlocks go out as **one** `AchievementCelebration`.
  Several unlocks show as "N ACHIEVEMENTS UNLOCKED" with the existing
  "+N more", never as one overlay after another.
- Completed Arcs are backfilled **silently**: nothing is celebrated for an
  Arc from months ago.
- The guard is a convenience. Correctness doesn't depend on it: the home
  Arc is reconciled on every run, and the backfill is idempotent.
- The board and summary of a completed Arc re-read when the backfill stores
  something. An Arc History card that is already built keeps its count
  until it is built again (it's disposed when it scrolls away or the
  screen closes). The launch-time run starts before any navigation, so in
  practice the card is built after the backfill.

### Current-day reversibility (Phase 10A) holds for all 32

Past unlocks are permanent. Today's are provisional. The generic
reconciliation removes any unlock dated today that today's history no
longer earns, whichever achievement it is. Tests prove this for new keys
first reached today: a 14-day streak undone, the 25th Perfect Day lost,
the 30th Workout / Water / Learning day and the 30-day No Junk Food run
undone. Each comes back exactly once when earned again. The product has no
way to delete a reflection, so a reflection total can't be undone.

## 5. Achievements screen

The collection is grouped and scrolls as one list; there are no tabs:

```
COLLECTION
18 of 32 unlocked
[overall progress bar]

PROGRESS 1 / 4
[2-column cards]
CONSISTENCY 3 / 9
...
JOURNEY 1 / 5
```

- Each category heading is real text, marked as a semantics **header**
  with a label like "Habit Mastery, 1 of 7 unlocked". Headings aren't
  buttons.
- The two-column cards, the locked / unlocked styling, the card semantics
  (title, locked or unlocked with day and date, criterion) and the Phase
  10B detail sheet and Share action are reused unchanged. A locked
  achievement still can't be shared.
- At 2× text nothing overflows, every heading and description reads, the
  Journey section is reachable, and the detail sheet and Share stay
  reachable. Text scaling isn't clamped.
- Motion: none added. The existing unlock reveal covers the new badges,
  and reduced motion is still authoritative.

## Compatibility locks

| | |
|---|---|
| Database schema | **v5**, unchanged (no new table or column; ids are plain strings) |
| Backup | export **format 2**; import formats 1 and 2. No format 3 |
| Version | `1.0.0+1`, unchanged |
| `applicationId` | `com.nextrep.nextrep` |
| XP | rules and values unchanged; achievements grant 0 XP |
| Existing ids | habit and `AchievementKey` ids unchanged; additions only |
| Dependencies | none added |
| Permissions | unchanged (below) |

Backups carry the new template ids and achievement ids as ordinary values.
The existing rules for unknown achievement keys are unchanged: a key this
version doesn't know is never exported, and a file containing one is
rejected on import.

> **Note: older versions.** Because v1.0's validator rejects achievement
> keys it doesn't know, a v1.1 backup that contains one of the 17 new
> unlocks can't be restored into **v1.0**. Restoring into v1.1 or later
> works, and so does every v1.0 backup on v1.1. Downgrade restore was never
> a supported path, and changing it would mean changing an already-released
> version.

### Android permissions (release APK, `aapt2 dump permissions`)

```
uses-permission: android.permission.RECEIVE_BOOT_COMPLETED
uses-permission: android.permission.VIBRATE
uses-permission: android.permission.POST_NOTIFICATIONS
permission:      com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

No INTERNET, storage, media, contacts, usage-access, accessibility
service, camera or microphone permission. The debug APK's INTERNET
permission comes from Flutter's standard `src/debug` manifest, which this
phase doesn't change. `android/`, `ios/`, `pubspec.yaml` and
`pubspec.lock` are unchanged.

## Privacy

- The rules read stable habit ids, dates, `DayRecord` completion and streak
  marks, and reflection *dates*. They never read reflection text, mood,
  custom titles or logged bedtimes.
- Nothing new is logged. Errors go through the existing `ErrorReporter`
  with no data.
- No network, analytics, account or backend.

## Tests

New in this phase (73):

| File | Tests | Covers |
|---|---|---|
| `test/domain/phase10c_achievement_rules_test.dart` | 33 | below / exact / later / today-undone for every new rule; disabled days, misses and Minimum Days; seasonal participation (joined Day 15, joined Day 61); stable-id vs title (renamed counts, custom lookalike and legacy `sleep_on_time` don't); Water target-agnostic; Sleep by completion only; titles and icons never change the result |
| `test/domain/phase10c_catalog_test.dart` | 20 | the six templates field by field; no medical wording; icon and accent for every key; starter set unchanged; setup add, enabled, duplicate rejected, 12-habit limit, not seeded, a running Arc gains nothing; catalog of 32 with each key once; old ids identical, new ids unique snake_case; deterministic order; category sizes 4 / 9 / 3 / 7 / 4 / 5; titles; 32 distinct glyphs and palette accents |
| `test/domain/phase10c_backfill_test.dart` | 7 | A: an upgraded active Arc gets exactly its 11 earned unlocks with historical dates, old and unknown rows untouched, no XP; B: idempotent; C: one combined celebration; D: a completed Arc backfilled silently; E: several completed Arcs, no cross-session contamination, setup skipped; F: new achievements reached today are revoked and restored once (14-day streak, Perfect Day 25, Day 30 totals and run); Water honours a raised goal and Minimum Days |
| `test/data/phase10c_backup_test.dart` | 5 | schema v5, format 2; a v1.0-era format-1 backup restores and backfills from its own history; a format-2 restore needs no further backfill; new template and achievement ids round-trip; unknown keys follow the existing rule |
| `test/features/phase10c_flow_test.dart` | 5 | six headings in order, each of the 32 cards under its category, header semantics, locked / unlocked labels; a new achievement opens details and shares a 1080 × 1350 PNG writing nothing, a locked one can't; 2× text; the upgrade celebration as one card; the picker shows the six templates with their goals and icons, Hair Care is added once |
| `test/features/share_card_render_test.dart` | +3 | Today's Progress and My Arc with 12 habits including the six new templates (no overflow, 1080 × 1350, own accents); every one of the 32 achievement cards renders |

Existing tests updated, only for the larger catalog: counts (15 → 32), the
category display order, and completed 92-day Arcs that now also hold
Day 14 / 60 / 75. The migration v4 test now asserts that a completed
v3-era Arc gains exactly those three milestones on their historical dates,
with no duplicates.

### Results

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` | **766 / 766** (693 before) |
| Migrations | 39 / 39 |
| Backup (format 1 + 2, incl. Phase 10C) | 76 / 76 |
| Phase 10A (flow + reconciliation) | 21 / 21 |
| Phase 10B (flow + card data + render) | 61 / 61 |
| Phase 7 lifecycle + accessibility | 30 / 30 |
| Phase 10C new | 70 / 70 (+3 in the render test) |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS (local; not a release candidate, not staged) |
| `flutter build ios --simulator` | PASS |

## Deferred

- Adding a brand-new habit to a running Arc and dated "habit exists from"
  semantics (needs its own architecture decision).
- Scheduled habits (weekdays, 3× a week).
- Water smart reminders and Focus Guard / social-media monitoring (v1.2
  planning; no UsageStatsManager).
- Accounts, friends, couple linking, leaderboards, cloud, analytics, a
  remote achievement catalog.
- Achievement XP. Medical or nutrition recommendations.
- v1.1.0 version bump, release notes, signed APK and physical
  qualification (Phase 10D).
