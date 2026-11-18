# Phase 12E1: v1.3.0 lifecycle foundation

## Objective

The storage, migration, backup and domain foundation that the v1.3.0
Freeze (12E2) and Restart (12F) features, and the Weekly Review (12B) and
Calendar (12C), build on, exactly as the merged
[Phase 12A Addendum](PHASE_12A_ADDENDUM.md) specifies (AD5–AD11, AD16,
AD17, AD19, §§ F1, F2, G, H, L1, L7) together with
[ARC_CONTROL_SPEC.md §§ 3, 5, 6](ARC_CONTROL_SPEC.md) and
[ARC_MOMENTUM_SPEC.md § 12](ARC_MOMENTUM_SPEC.md#12-lifecycle-addendum-freeze-and-restart).

**No user-facing feature.** Nothing in the app can create a freeze or end
an Arc yet: no Freeze, Resume or Restart action, no new screen or setting,
no sound. Synthetic tests build paused and ended Arcs; a format-4 backup
can carry them. Version unchanged (`1.2.0+3`); no release.

## Baseline

| | |
|---|---|
| `origin/main` | `933960c6b8b8e4f69b1823a12df7cbe6e9f95468`, "Phase 12A Addendum … (#23)", the expected baseline; nothing landed after it |
| Before | schema v6, backup writes format 3 (reads 1–3), Focus Guard native gate 6 |
| Worktree | `~/labs/NextRep-12E1`, branch `phase/12e1-v1.3-lifecycle-foundation`, new; the primary checkout and the other worktrees were not touched |

## Schema v7 (one additive step)

`AppDatabase.schemaVersion` 6 → 7, step `from6To7`, generated with the
documented drift workflow (`build_runner`, `schema dump`, `schema steps`,
`schema generate`): `drift_schemas/drift_schema_v7.json`, `Schema7` in
`schema_versions.dart`, `test/generated_migrations/schema_v7.dart`. The
v1–v6 snapshots and steps are unchanged (the generated database code diff
is purely additive).

```
winter_arc_sessions  + "closed_on" TEXT NULL
CREATE TABLE "arc_freezes" ("session_id" INTEGER NOT NULL REFERENCES winter_arc_sessions (id) ON DELETE CASCADE,
  "frozen_from" TEXT NOT NULL, "resumed_on" TEXT NULL, "requested_at" INTEGER NOT NULL, "resumed_at" INTEGER NULL,
  PRIMARY KEY ("session_id", "frozen_from"), CHECK (resumed_on IS NULL OR resumed_on > frozen_from))
CREATE UNIQUE INDEX one_open_freeze ON arc_freezes (session_id) WHERE resumed_on IS NULL
CREATE TABLE "feedback_preferences" ("id" INTEGER NOT NULL CHECK("id" = 1), "sounds_enabled" INTEGER NOT NULL
  CHECK ("sounds_enabled" IN (0, 1)), "sound_theme" TEXT NOT NULL CHECK("sound_theme" IN ('iceCrystal', 'summitSpark',
  'warmEmber')), "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"))
```

This is the SQL SQLite stores, asserted verbatim by `migration_v7_test`;
it is addendum § G. `single_open_session` is unchanged, so an `ended` Arc
is outside it. No row is read, rewritten, deleted or backfilled.

**Implementation finding: atomic step.** Drift records `user_version`
after each step but does not run a step in a transaction. A failure-
injection test showed that a v6 → v7 upgrade failing after its `ALTER
TABLE` left the column behind with `user_version` still 6, so every later
launch would fail on "duplicate column". `from6To7` therefore runs its DDL
and `PRAGMA user_version = 7` in one transaction: a failed upgrade leaves
the v6 database exactly as it was, and the next launch retries it. The
older steps are untouched.

## Domain: `ended`, freeze intervals, day ↔ date mapping

- `WinterArcStatus.ended` (persisted by name) with `isUnfinished` (setup,
  active) and `isFinished` (completed, ended). `WinterArcSession` gains
  `freezes` (`ArcFreeze`: `[frozenFrom, resumedOn)`, open while
  `resumedOn` is null) and `closedOn`. Existing Arcs: no freeze, null.
- `WinterArcRules.problemWith` (also the backup's arc check) adds: freezes
  only on started Rolling Arcs; ordered, non-empty, never overlapping or
  touching (a lived challenge day between two); each after the first day
  and before Day 92; at most one open, the last, only on an active Arc;
  rolling end = `start + 91 + closed paused days`; `closedOn` exactly for
  `ended`, on one of its challenge dates; no pause after `closedOn`.
- Mapping on the session: `dayNumberOf` (null on a paused date),
  `dateOfDay` (null for a day after the start of an open pause: never an
  estimate), `isFrozenOn`, `isParticipatingOn` (not paused, not after
  `closedOn`), `isOpenOn` (`openToday`: participating and not ended),
  `participatingDatesThrough` (jumps over pauses; stops at `closedOn`),
  `isOverOn` (never while paused), `positionOn` (new `ArcPaused`,
  `ArcEnded`), `hasChallengeDayOnOrAfter`, `lengthInDays` = challenge days
  (92), `calendarSpanInDays`, `pausedDays`. Paused dates are found from
  interval bounds; nothing walks them.
- **Zero-freeze guarantee:** for Arcs without a freeze or `closedOn` every
  member returns exactly v1.2.0's value (property test against v1.2's
  arithmetic, copied verbatim, for 500+ generated rolling and seasonal
  Arcs, every day 1–92 and beyond, every date from before the start to
  after the end, and far dates).

### Readers moved onto the mapping (addendum § F1)

| Reader | Change |
|---|---|
| `ArcHistory` | `journey()` lists Days 1–92 through `dateOfDay` (`JourneyDay.date` nullable for an undated day); streak `pending` only on the open day (`isTodayOpen`), so an ended Arc's unachieved `closedOn` is a miss; its days after `closedOn` are the ninth state `notReached`; `closedOn` takes its final state, never `today` |
| `AchievementRules` | Day milestones via `dateOfDay`; **Summit never for an `ended` Arc**; unlocks never re-dated |
| `AchievementBoard` | Unlock day numbers subtract earlier pauses |
| `HabitTrackingService` | `_nextChallengeDay`: tomorrow while a challenge day remains (a revision may be dated the first paused date, AD6); none on a paused date |
| `ArcLifecycleService` | Freeze-aware `isOverOn`: a paused Arc never completes; ended Arcs untouched |
| `ReminderPlanner`, `HydrationDay` | Already on `positionOn` / `isParticipatingOn`: nothing planned on a paused date; day numbers continue after a pause |
| Labels, Today hero, Journey, share data | Fallbacks for `ArcPaused` / `ArcEnded`; an open pause prints no end date |
| Journal | Day number nullable (never null in practice: reflections are on challenge days) |

Readers verified unchanged: `DayRules`, XP, `DaySummary.isTrackable`,
`ReflectionService` (both already require `active` and participation),
`ArcSummary` (iterates `elapsedDates`), share/scene day totals (92).

### Status comparisons (addendum § F2, re-inventoried)

Every `WinterArcStatus` site was searched again; the classification:

| Site | Before | Now |
|---|---|---|
| `BackupValidator.validate`, `BackupSummary.of` | not completed = unfinished | `isUnfinished`; an ended Arc is neither completed nor unfinished |
| `InsightRules.compute` | not completed = **the** active Arc | exhaustive switch: completed counts, active is active, ended neither (its days still count) |
| `DriftWinterArcRepository.latestCompletedSession` | newest completed | newest finished (completed or ended); name kept for existing callers, documented |
| `WinterArcService._reusable` | latest completed | latest finished; `configOn(endDate)` includes a revision waiting at the end (AD11) |
| `AppRoutes.forSession` (exhaustive) | – | ended → its read-only summary |
| `ArcHistoryTile`, `SummaryScreen` heading | completed wording for every non-active Arc | "ENDED EARLY" / "… ENDED EARLY" fallback; never "complete" |
| `deleteCompletedArc`, Summary's Delete | completed only | unchanged (deletion of ended Arcs is Phase 12F); orphan check now covers `arc_freezes` |
| Others (`DaySummary`, tracking, reflections, reminders, setup, achievement backfill, history, restore preview) | – | already explicit (`== active`, `!= setup`, `== setup`): correct for `ended` |

### Clock guard (AD19)

`ArcClockGuard.check` (pure) and `ArcClockGuardService` (reads
`lastActivityDate` through `DriftArcActivityRepository` and today from the
injected `Clock`): safe only when today ≥ participation start, ≥ the latest
activity date (progress, day modes, XP, reflections, unlocks; **never**
goal revisions) and ≥ the latest `resumedOn`. Read-only; it names the
bound and the earliest safe date. Not called before any write yet (12E2,
12F re-check it inside their transactions).

### Feedback settings

`SoundTheme` (`iceCrystal`, `summitSpark`, `warmEmber`),
`FeedbackPreferences` (defaults: sounds on, Ice Crystal) and
`DriftFeedbackPreferencesRepository`: no row reads as the defaults and
reading never inserts. No screen and no player (12G).

## Backup format 4

Writes 4; reads 1, 2, 3, 4. Format 4 = format 3 plus, per Arc,
`closedOn` and `freezes` (`frozenFrom`, `resumedOn`, `requestedAt`,
`resumedAt`), the status `ended`, and `data.feedback`
(`{soundsEnabled, soundTheme}` or null). Formats 1–3 keep their frozen
field sets **and status lists** (an older file can't say `ended`), and
read with no freeze, no `closedOn` and no feedback. Same product,
checksum, size limit, strictness and error privacy (positions and rule
names only).

Validation adds (addendum § H): every `problemWith` rule above; a pause
starts no later than the day after the export and was resumed no later
than the export; `closedOn` not after the export; no activity on a paused
date or after `closedOn` (via `isParticipatingOn`). **Goal revisions are
configuration:** they must lie between the participation start and the
end date (and ≤ export + 1 day) but may fall on a paused date or after
`closedOn`.

Restore (one transaction, verified counts, no dangling references):
replaces `arc_freezes` and `closed_on` too; reminders and Focus Guard off
as before; the sound setting is replaced only by a format-4 file (null:
back to the defaults); a format 1–3 file keeps the device's own. A
restore never plays a sound.

## Focus Guard native schema gate

`FocusGuardStore.SCHEMA_VERSION` 6 → 7, with the exact-version gate in
`FocusGuardStore.supportsSchema` / `hasSupportedSchema` (used by
`FocusGuardDatabase.withStore`) so it is JVM-testable. `DriftFixture` is
schema 7 by default and can build another version. Focus Guard's tables
are unchanged since v6 (asserted against the v6 snapshot). No Freeze logic
in Kotlin; no new permission.

## Automated validation

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` (all) | 1399 passed, 0 failed (v1.2 baseline suite plus 135 new) |
| New: `migration_v7_test` | 28: fresh v7 SQL verbatim; v1–v6 → v7; v6 → v7 with realistic data (active Arc and saved-setup variants) row for row; objects unchanged; FK, integrity, unfinished uniqueness; nothing awarded; reopen without re-migrating; failed upgrade atomic and retryable |
| New: `backup_v4_test` | 42: format-4 writing; restore of scheduled and open freezes and an ended Arc (fresh install row-identical to the source); round trip; paused Arc restored paused, its waiting revision applying after the pause; sound present / absent; formats 1, 2, 3 keep the device's sound; 35-item matrix of rejections, each with nothing written; failure injected inside the restore transaction (freeze and feedback inserts), then retry |
| New: `arc_date_mapping_test` | 24: v1.2 equality; 400 generated paused Arcs against a brute-force calendar walk (inverse mapping, paused dates have no day, no day mapped twice, 92 days, span); elapsed dates; never over while paused; later freezes never move lived days; a 400 000-date pause without walking it; worked cases; validation |
| New: `lifecycle_foundation_test` | 26: status classes; ended streaks and Journey; paused streaks and Journey; spec § 12.5.2 partition and § 12.5.1 XP groups for generated Arcs of every status and every date, plus worked examples D′, D, E, F, G, H, I and XP examples D–H; Summit never for ended; milestones on mapped dates; Insights; reminders and Hydration skip paused dates; clock guard incl. the "never overlaps" property |
| New: `lifecycle_storage_test` | 15: freezes / `closedOn` loaded by every lookup; ended Arcs as history and outside `single_open_session`; cascade deletion; SQL constraints; paused Arc never completes, resumed one completes after the moved Day 92; ended Arc untouched and no Summit; every write refused on a paused date with nothing written; revision dated the first paused date; `lastActivityDate` per table and never revisions; clock-guard service read-only; feedback storage |
| Updated (version constants only) | migration chains target v7 (the "current schema" assertion moved to `migration_v7_test`; "v6 columns" comparisons ignore `closed_on`, as 11B did for v6); format 3 → 4 and "future" version 4 → 5 in backup and release-identity tests; Focus Guard `user_version` 6 → 7 |
| Native JVM (`:app:testDebugUnitTest`) | 71 / 71, including the gate: 7 accepted, 0/5/6/8/9/70/−1 refused, a schema-6 and a schema-8 file left alone, schema 7 reads and claims once |
| Android debug and release builds | both build; release audit (CI's script, run locally): exactly the expected permission set, no forbidden service, provider not exported, R8 keeps intact |

## Emulator qualification (disposable AVD, real v6 → v7 upgrade)

A new AVD `NextRep12E1_API36` (Android 16, `sdk_gphone64_arm64`,
google_apis), created for this phase and deleted afterwards. No other
emulator and **no physical device** was attached or used. Only debug-key
builds; no production signing, no official APK.

| Step | Result |
|---|---|
| v1.2 baseline | debug build of `933960c` (`1.2.0`, code 3) installed fresh; its first launch created a schema-v6 database |
| Synthetic v6 data | written into that database on the host (completed rolling Arc with a revision, a Minimum Day and a reflection; completed late-joined Seasonal Arc; active rolling Arc on Day 6 with custom, binary and disabled habits in a chosen order, a pending revision for tomorrow, progress and XP; reminders on; Focus Guard on, 1-minute budget, Settings selected), pushed back with `run-as`; Usage Access and notifications granted |
| v1.2 on that data | Today "Day 6 of 92", 330 XP; its own achievement backfill; its Focus Guard worker ran (`BELOW_BUDGET`). This state, pulled, is the v6 reference |
| In-place upgrade | `adb install -r` of the 12E1 debug build (same debug signer, same package `com.nextrep.nextrep`, version still `1.2.0`/3). Before the first launch the file was still v6 |
| Migration | first launch: `user_version` 6 → 7, integrity `ok`, no foreign-key violation; **all 11 v6 tables row-for-row identical** (98 rows); `closed_on` NULL on the 3 Arcs; `arc_freezes`, `feedback_preferences` and `one_open_freeze` created, empty; every other schema object unchanged |
| App after upgrade | the same Today (Day 6 of 92, 330 XP, 6/32 achievements, no new unlock); Journey dates and Arc History ("COMPLETED" labels) as before |
| Habit tracking | through the UI: Water 2 → 3 (no XP), "Paper journal" completed (+15 XP, one ledger row, 330 → 345) |
| **Focus Guard natural runs** (WorkManager's own periodic schedule, nothing forced) | 00:50 `NUDGED`: one `focus_guard` notification posted, `last_nudged_on` claimed in the schema-7 database; 01:05 and 01:20 `ALREADY_NUDGED`: no duplicate |
| Permissions | requested and granted permissions identical before and after; Usage Access kept |
| Process death | `am kill`, `force-stop` and two relaunches: no error (the step isn't re-run), integrity `ok`, v7; only the deliberate taps and the nudge claim differ from the v6 reference |
| Minified build | the R8 release build (debug key, as CI) installed in place: starts cleanly (no `NoSuchMethod` / crash), same state, database pulled with `adb root`: v7, integrity `ok` |

The failure path of the migration and the "schema 6 left alone" gate are
covered by `migration_v7_test` (atomic, retryable) and the JVM gate tests.

## Independent review corrections (R1, R2)

The independent review of `85f78b7` approved the migration, backup,
mapping, Focus Guard and emulator evidence and raised two Ended-Arc
defects. Both are fixed without touching the schema, migration, backup,
Focus Guard, manifest, version or dependencies.

| | Root cause | Correction |
|---|---|---|
| **R1** Journey "today" on an ended Arc | `ArcHistory._journeyDay` gave `JourneyDay.isToday` the calendar test `date == today`. The day's *state* already followed `isOpenOn`, but with `closedOn = today` the settled last day was still marked, announced ("Day 3. Today. Partial…"), labelled "TODAY · Day 3" and scrolled to as the open day | `isToday` is the open day only (`date == today && session.isOpenOn(today)`, spec § 12.5.2); an ended Arc marks no day, not even before joining. Active, completed (rollback included), paused and late-join presentation is unchanged. `JourneyPath`: without a today marker an ended Arc now opens on its last lived day (it opened at the summit), and its trail never reaches the Summit, even when `closedOn` is Day 92 (it would have read "Summit, Day 92, reached") |
| **R2** Achievement writes to ended Arcs | `AchievementService.sync()` (and `reconcile()`) reconciled the home Arc, which is an ended Arc when nothing newer exists; `backfillCatalog()` reconciled every non-active Arc. Both reached `reconcileUnlocks`, which inserts missing unlocks and revokes unlocks dated today | One guard in `AchievementService._reconcile`, the only path that writes an unlock outside a restore: an ended Arc returns no change and its history is not evaluated. `sync`, `reconcile`, both backfill paths and the app's launch run are covered; boards still read the stored unlocks. Completed Arcs keep their backfill and natural-completion Summit; active Arcs keep provisional unlocks |

Tests (12 new or corrected detectors fail on `85f78b7` and pass now; the
rest are Active / Completed / paused controls). `flutter test`: 1415
passed, 0 failed (16 new).

- `lifecycle_foundation_test`: the old assertion `isToday == true` on
  `closedOn` corrected to false; new group "Journey today marker": on
  `closedOn` with a Perfect, Minimum, Partial and Missed last day; after
  `closedOn` and after the planned end; after a rollback before `closedOn`
  (F4-4); an ended late-joined Seasonal Arc; paused dates (open and closed
  pause); active controls (every state, a scheduled freeze); a completed
  Arc after a rollback keeps its open today. The generated-Arc property
  test now also checks the marker for every status and date.
- `journey_ended_arc_test` (new, widget): no "Today" in any semantics
  label and no "TODAY" label for an ended Arc on `closedOn`; it opens
  centred on its last day while the active Arc of the same date opens on
  today with its label; an Arc ended on Day 92 never shows the Summit
  reached, a completed one does.
- `ended_arc_achievements_test` (new, in-memory Drift): an ended Arc with
  valid unlocks, unlocks dated `closedOn`, a missing one, unearned rows a
  reconciliation would revoke and a stored Summit. `sync`, `reconcile`,
  `backfillCatalog` and app launches, each run three times, leave every
  table byte-identical and report nothing: as the home Arc, with a newer
  active Arc, with a newer completed Arc, from a format-4 restore; on
  `closedOn`, after it, after its planned end and after rollbacks. An Arc
  ended on Day 92 never gains a Summit. Controls: the active Arc gains,
  loses (provisional) and celebrates its own unlocks; the completed Arc is
  backfilled silently and earns its Summit; then everything is idempotent.
- `lifecycle_storage_test`: "an ended arc is left untouched" relied on the
  defect (the backfill stored First Rep on the ended Arc); it now stores
  the unlocks while the Arc is active and requires the backfill to write
  nothing.

## Known limitations

- Nothing creates a freeze or an ended Arc; their wording on existing
  screens is a minimal fallback for restored synthetic data, to be
  designed in 12E2 / 12F.
- `latestCompletedSession` / `ArcResolution.latestCompleted` keep their
  names but mean "latest finished".
- After the in-place update and before the app is first opened, the
  database is still v6 and the updated native worker leaves it alone
  (exact-version gate); Focus Guard resumes once the app has opened and
  migrated. This is the designed gate (addendum C6).
- No genuine format-3 file is committed; format 3 is tested as the
  format-4 export minus its additions (formats 1 and 2 use genuine files).
- Independent review notes fixed before the PR: a not-reached day is
  never "today" and the Journey trail ends at the last lived day; an
  ended Arc's participation length stops at `closedOn`; its summary scene
  isn't the summit.
- Weekly Review, Calendar, Freeze, Restart, sounds: later phases.
