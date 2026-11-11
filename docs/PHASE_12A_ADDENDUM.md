# Phase 12A Addendum: v1.3.0 Arc Control and Personalization

## A. Objective and boundary

The owner added five features to the approved v1.3.0 plan
([PHASE_12A.md](PHASE_12A.md), PR #22): habit reordering in setup, a
saved setup with an explicit start confirmation, Freeze for Rolling Arcs,
Restart with the same setup (and an optional deletion of the old Arc), and
completion sounds. This addendum investigates them against the source,
decides the architecture, and updates the roadmap. The release target is
unchanged: **NextRep v1.3.0 — Arc Momentum**.

This is a **documentation-only** phase. No file under `lib/`, `android/`,
`ios/`, `test/`, `integration_test/`, no `pubspec.*`, workflow, release
tool, schema, backup format, version or signing configuration changed. No
package was added, no APK built or installed, no audio asset generated, no
emulator or physical device used, and no user data or backup touched.

| Document | Purpose |
|---|---|
| This file | Baseline, source findings, decisions with alternatives, data model, migration and backup verdicts, risks, test plan, owner decisions |
| [ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md) | User stories, state machines, the rules of each feature, text wireframes, acceptance criteria |
| [ARC_MOMENTUM_SPEC.md § 12](ARC_MOMENTUM_SPEC.md#12-lifecycle-addendum-freeze-and-restart) | The exact changes Freeze and Restart require in the Weekly Review and Calendar rules |
| [V1_3_ROADMAP.md](V1_3_ROADMAP.md) | The expanded phase plan, dependencies and gates |

Labels: **CONFIRMED** (verified in the source at `main` `64d77e0`),
**PROPOSED** (a design decision of this addendum), **UNRESOLVED** (needs
the owner's decision or later qualification on a device).

**Summary of outcomes**

| Item | Result |
|---|---|
| Habit reordering | Uses the existing `habits.sort_order`. One new repository write. **No schema or backup change.** |
| Save setup for later | The persisted `setup` session **already is** the saved draft. New: a saved-setup hub, a review screen and a start confirmation. **No schema or backup change.** |
| Freeze (Rolling only) | **Feasible without rewriting history.** Persisted freeze intervals; the day number is derived. Takes effect at the next local day boundary. Needs a new table. |
| Restart | A new Arc cloned from the current effective setup, in one transaction. The old Arc becomes `ended` (never `completed`), with its history kept. Needs one column and one status value. |
| Delete old Arc | A separate action after a successful restart, with its own typed confirmation. Reuses the existing whole-Arc deletion. |
| Sounds | A small native player behind a Dart interface, no new dependency recommended. Needs a settings table. |
| Database migration for v1.3.0 | **YES: schema v7**, additive only (2 tables, 1 nullable column). This replaces Phase 12A's "NO", which was correct for the two read-only features alone. |
| Backup-format change for v1.3.0 | **YES: format 4** (write 4, read 1–4). v1.2.0 rejects format 4 safely. |
| Weekly Review and Calendar | Their rules stay valid. They must use a day ↔ date mapping instead of `startDate + (d − 1)`; five additions are listed in spec § 12. |
| Stop conditions (brief § 22) | **None triggered.** |

## B. Verified baseline

Checked on 11 November 2026, before any change.

| | |
|---|---|
| `origin/main` | `64d77e0e5c8e3e9756c22d81b1d2e831fb44ad51`, "Phase 12A: plan v1.3 Arc Momentum architecture (#22)". It is still the Phase 12A merge commit; nothing has landed since |
| Phase 12B work | **None exists.** No branch, worktree or PR after #22 (`git branch -a`, `gh pr list --state all`) |
| Version (source) | `1.2.0+3` (`pubspec.yaml`), unchanged |
| Database schema | v6 (`AppDatabase.schemaVersion`), unchanged |
| Backup | writes format 3, reads 1 / 2 / 3 (`BackupFormat`), unchanged |
| Primary checkout | `~/labs/NextRep` on `phase/11b-smart-hydration` at `15392ce`, clean; **not touched** |
| Other worktrees | `NextRep-12A`, `NextRep-phase11c` … `NextRep-phase11f`; **not touched** |
| This worktree | `~/labs/NextRep-12A-Addendum`, branch `phase/12a-addendum-arc-control`, created from `64d77e0`. Neither existed before |

## C. Source findings (CONFIRMED)

Every path below exists at `64d77e0` (checked by script, § M).

### C1. Setup, saved state and start

| Finding | Source |
|---|---|
| An Arc being configured is a persisted session with status `setup`. It is created with its habits in one transaction | `WinterArcService.beginSetup` / `startNewArc` → `DriftWinterArcRepository.createSetupSession` |
| Every setup change is its own committed write, then re-read: toggling, adding a template or custom habit, editing, removing | `HabitSetupController._change` (`lib/features/habit_setup/habit_setup_controller.dart`); `DriftHabitRepository.addSetupHabit` / `updateSetupHabit` / `deleteSetupHabit` / `setEnabled` |
| The app reopens into the saved setup: `AppRoutes.home` returns `/setup` whenever a setup session exists | `lib/app/router/app_router.dart` |
| At most one unfinished session (setup or active) exists | unique index `single_open_session` (`lib/core/database/tables.dart`), re-checked in `createSetupSession` |
| A rolling setup's dates are provisional. Day 1 is assigned when Start is pressed: `startDate = today`, `endDate = today + 91`, `participationStartDate = today` | `ArcStartRules.start` (`lib/domain/winter_arc/winter_arc_service.dart`) |
| A seasonal setup can be created from 1 September, started only 1 October – 31 December, and is never moved to another year. The domain enforces this whatever the UI shows | `ArcStartRules.stateOn` / `start`, `SetupStartState`, `SeasonalWinterRules` (`arc_kind.dart`) |
| Start needs at least one enabled habit and is idempotent. There is **no confirmation step**: one tap on "Start Winter Arc" starts the Arc | `WinterArcService.startWinterArc`; `HabitSetupScreen._start` |
| A setup can be empty for a moment; it just can't start | `deleteSetupHabit` doc; `ArcSetup.canStart` |
| Cancelling a setup deletes it after a dialog | `HabitSetupScreen._cancelSetup` → `ArcRemoval.cancelSetup` → `deleteSession(expected: setup)` |
| A setup session is exported and restored like any Arc; the validator allows it and requires it to have no history | `BackupValidator._checkArc` ("an arc in setup has no history") |
| From the setup screen only About is reachable. Reminders, Data & Backup and Focus Guard have routes that work in every state, but no entry point here | `HabitSetupScreen` (`AboutLink` only); `AppRoutes.redirect` |

### C2. Habit order

| Finding | Source |
|---|---|
| `habits.sort_order` exists (integer, no unique constraint in SQL) and every read orders by it | `Habits.sortOrder`; `DriftHabitRepository.habitsForSession`; `loadHabitHistory`; `HabitHistory` constructor |
| New habits are appended at `max + 1`; editing keeps the order; "Reuse last setup" copies it | `SetupHabitRules._nextSortOrder`, `edit`; `WinterArcService._withConfig` |
| Backups carry `sortOrder` (0..9999) and reject duplicates within an Arc | `BackupCodec` (`h.integer('sortOrder', min: 0, max: 9999)`); `BackupValidator` ("duplicate sort order") |
| **Nothing can change a sort order after creation.** `updateSetupHabit` writes title, targets, unit, icon and enabled only | `DriftHabitRepository.updateSetupHabit` |
| Display order is a tie-break in the approved Weekly Review highlights | [ARC_MOMENTUM_SPEC.md § 4.4](ARC_MOMENTUM_SPEC.md#44-highlights-most-consistent-and-room-to-grow) |

### C3. The date model Freeze must respect

| Finding | Source |
|---|---|
| The day number is pure arithmetic: `dayNumberOf(date) = startDate.daysUntil(date) + 1` | `WinterArcSession` |
| A rolling Arc must span exactly 92 calendar days: `endDate == startDate + 91`. Services check this before persisting, and restore rejects anything else | `WinterArcRules.problemWith`; `BackupValidator._checkArc` |
| The elapsed days of an Arc are every date from the participation start to `min(today, endDate)` | `participatingDatesThrough`; `ArcHistory.elapsedDates` |
| Journey lists `lengthInDays` days as `startDate.addDays(i)` | `ArcHistory.journey()` |
| Close-out is date-driven: an active Arc becomes `completed` on the first local date after `endDate`, at app entry points. There is no background job | `ArcLifecycleService.reconcile` |
| **Every stored history row is keyed by calendar date, never by day number**: progress, day modes, XP (`habit_completed:<habit>:<date>`), revisions, unlocks, reflections | `tables.dart`; `XpRules.habitCompletionKey` / `perfectDayKey`; `DailyReflections` doc ("the challenge day number isn't stored") |
| Writes are only possible for today, on a participating date of the active Arc | `HabitTrackingService._trackableSession`; `ReflectionService`; `DaySummary.isTrackable` |
| Streaks are computed over `elapsedDates` only; a date that isn't in the list can neither grow nor break a streak | `ArcHistory.habitMarks` / `perfectMarks`; `StreakRules.compute` |
| Reminders are one-shot notifications per concrete date, re-planned on every reconcile. Nothing is planned without an active Arc or outside its days | `ReminderPlanner.plan`, `_forKind` (`arc.positionOn(date)`); `ReminderService._reconcile` |
| Hydration Coach paces only on participating dates | `HydrationDay.of` (`arc.isParticipatingOn(date)`) |
| Focus Guard is application-level, not owned by any Arc, and runs without an active Arc | `focus_guard_service.dart` doc; `AppRoutes.forReminder` |
| 31 files outside `winter_arc_session.dart` call the date helpers (`dayNumberOf`, `positionOn`, `lengthInDays`, `isParticipatingOn`, `endDate`, …) | `grep` inventory, § F1 |

### C4. Lifecycle, history and deletion

| Finding | Source |
|---|---|
| Three statuses, persisted by name: `setup`, `active`, `completed`. The `status` column has no SQL `CHECK` | `WinterArcStatus`; generated schema (`app_database.g.dart`) |
| "Reuse last setup" already clones an Arc's **final effective configuration** as a new baseline: same habit ids, titles, types, units, icons and order; target, minimum and enabled from the configuration in effect on the last day. Nothing else is copied | `WinterArcService.startNewArc(NewArcBaseline.reuseLast)`, `_reusable`, `_withConfig` |
| It is only available with nothing unfinished, from the latest completed Arc | `startNewArc` (`DomainRule.arcInProgress`); `SummaryScreen` (`isHome`) |
| XP, levels, streaks and achievements are per Arc. There are no cross-Arc achievements: unlocks are keyed `(session_id, achievement_key)` and evaluated from one Arc's history | `ProgressRepository.totalXp(sessionId)`; `AchievementUnlocks`; `AchievementRules.evaluate` |
| Insights are cross-Arc and derived on demand from every started Arc; nothing is stored | `InsightService.snapshot`; `InsightRules.compute` |
| A completed Arc can be deleted whole, in one transaction, with a check that no row is orphaned. A dialog states what is lost. Only `completed` Arcs can be deleted | `WinterArcService.deleteCompletedArc`; `DriftWinterArcRepository.deleteSession`; `_DeleteArcDialog` (`summary_screen.dart`) |
| A backup cannot hold a `completed` Arc whose end date has not passed | `BackupValidator._checkArc` ("a completed arc that has not ended") |
| The validator and the restore summary treat every status other than `completed` as "unfinished" | `BackupValidator.validate` (`status != completed`), `BackupSummary.of` |
| Insights treat every started Arc that is not `completed` as **the** active Arc | `InsightRules.compute` (the `else` branch sets `active`) |

### C5. Feedback and settings

| Finding | Source |
|---|---|
| No audio exists. Feedback is haptic only, called after the write is persisted | `lib/shared/feedback/haptics.dart`; `rg -i 'sound\|audio'` finds only notification permission flags |
| The habit-completion haptic fires when a commit's ledger grants this habit's award, i.e. on a persisted incomplete → complete transition, and is skipped when the same commit grants the Perfect Day bonus (the celebration card has its own) | `TodayScreen._perform` (`ledger.habitAwardFor(habit.id)`, `ledger.perfectDayGranted`) |
| `ProgressTransition.becameCompleted` / `becameIncomplete` describe the transition | `lib/domain/progress/habit_progress_rules.dart` |
| There is no key-value settings store. Settings are single-row tables (`reminder_preferences`, `focus_guard_preferences`) | `tables.dart`; `pubspec.yaml` (no preferences package) |
| No audio package is a dependency | `pubspec.yaml` |

### C6. Platform coupling

| Finding | Source |
|---|---|
| **Focus Guard's native worker refuses any database whose schema version is not exactly 6.** With schema v7 and no native change, Focus Guard's background check would silently stop | `FocusGuardStore.SCHEMA_VERSION = 6L`; `FocusGuardDatabase.withStore`; `FocusGuardStoreTest.readsTheSchemaVersion` |
| Restore replaces every table in one transaction and leaves reminders and Focus Guard off | `DriftBackupStore.replaceAll`; `BackupService.restore` |
| The backup codec is strict: unknown fields and unknown enum values are rejected, and an unknown `formatVersion` is refused before anything is read | `BackupCodec.decode` (`only(...)`, `choice('status', WinterArcStatus.values, …)`, `readableVersions`) |

## D. What already exists, and what is new

| Feature | Reused as is | Genuinely new |
|---|---|---|
| 1. Reorder | `sort_order`, ordered reads, backup field, reuse copying the order | One repository method that rewrites the order in a transaction; the drag UI |
| 2. Save for later | The `setup` session, per-change persistence, launch into setup, date assignment at Start, seasonal rules, cancel, backup of a setup | Saved-setup hub, review screen, confirm-and-start screen, an explicit "Save for Later" action, settings links |
| 3. Freeze | Date-keyed history, today-only writes, elapsed-date streaks, per-date reminders | Freeze intervals (table), a day ↔ date mapping on the session, freeze service, frozen UI |
| 4. Restart | The clone of the effective configuration, per-Arc XP and achievements, Arc History | An `ended` status with a `closed_on` date, an atomic end-and-start transaction, the typed confirmation |
| 4b. Delete old Arc | Whole-Arc deletion, its orphan check and its dialog copy | Accepting `ended` Arcs; a typed confirmation |
| 5. Sounds | The post-commit feedback hook and its transition rules | A player, three sound sets, a settings table and screen |

## E. Decisions

Each decision uses the same rows. "Owner" says whether it needs the
owner's approval at Gate A2.

### AD1. Where the habit order is stored

| | |
|---|---|
| Question | Does reordering need new persistence? |
| Existing behavior | `habits.sort_order` orders every list; nothing rewrites it (C2) |
| Options | (a) Rewrite `sort_order` to `0..n−1` for the dragged list. (b) A new ordering table or a fractional-rank column |
| Evidence | C2: the column, the ordered reads, the backup field and the reuse path all exist |
| Trade-offs | (a) touches up to 12 rows per drop. (b) adds a migration for nothing |
| Risks | A partial write would leave duplicate orders, which a backup export would then reject. Mitigated by one transaction that also checks the id set |
| Recommendation | **(a).** New `HabitRepository.reorderSetupHabits(sessionId, orderedIds)`: inside one transaction, require the session to be in setup, require `orderedIds` to be exactly the stored ids, write `sort_order = index` |
| Owner | NO |

### AD2. When reordering is allowed

| | |
|---|---|
| Question | Setup only, or also in a running Arc? |
| Existing behavior | A running Arc's habits can be renamed, re-targeted from the next day or switched off. They cannot be added, removed or moved |
| Options | (a) Setup only. (b) Also while active |
| Evidence | The owner asked for ordering "during Arc setup". Display order is the final tie-break of the Weekly Review's highlights (spec § 4.4), and a completed week must never change (spec U2) |
| Trade-offs | (b) is cosmetically harmless for Today, but it could change which habit a finished week names as "Most consistent" |
| Risks | (b) breaks the approved "a finished week won't change" promise unless order were versioned by date |
| Recommendation | **(a) Setup only for v1.3.** The order chosen in setup is the order of the Arc. Restart and "Reuse last setup" carry it over, and the new setup can be reordered again |
| Owner | YES (confirm setup-only) |

### AD3. The saved-setup model

| | |
|---|---|
| Question | What stores a setup that is saved for later? |
| Existing behavior | The `setup` session is already durable, edited in place, reopened on launch, exported and restored (C1) |
| Options | (a) Reuse the `setup` session; one draft; keep per-change saving and add an explicit "Save for Later". (b) A separate drafts table, several drafts. (c) Buffer edits in memory and write only on Save |
| Evidence | C1. `single_open_session` allows one unfinished session. `HabitSetupController` doc: "Every change is persisted immediately (so leaving the app mid-setup keeps it)" |
| Trade-offs | (b) needs a schema change, a draft picker and new backup rules. (c) loses work on process death, which today's design prevents |
| Risks | (a): users may not realise the setup is already saved, so the explicit action and the hub say so |
| Recommendation | **(a).** No new state is stored. `DRAFT` and `READY_TO_START` are derived: a setup is ready when `ArcSetup.canStart` (season allows it and a habit is on). "Save for Later" writes nothing new; it confirms and leaves the editor |
| Owner | YES (one draft; autosave kept) |

### AD4. Start confirmation

| | |
|---|---|
| Question | How is starting separated from saving? |
| Existing behavior | One tap on "Start Winter Arc" starts immediately (C1) |
| Options | (a) A dedicated Confirm & Start screen reached from Review. (b) A dialog on the existing button |
| Evidence | `HabitSetupScreen._start`; the start itself is one atomic `updateSession` and is idempotent |
| Trade-offs | (a) is one more screen. It has room for the dates, the habit list and both actions side by side at 2× text; a dialog doesn't |
| Risks | An extra step for a first-time user. Acceptable: starting fixes 92 days |
| Recommendation | **(a).** Review Setup → Confirm & Start. The only code path that starts an Arc from setup is the confirm button. Day 1 is the local date at the moment of confirmation (`ArcStartRules.start`), re-read when the screen resumes or midnight passes |
| Owner | NO |

### AD5. How a freeze is represented

| | |
|---|---|
| Question | How can a Rolling Arc pause without redefining days already lived? |
| Existing behavior | Day number and end date are arithmetic on `startDate`; a rolling Arc must be exactly 92 calendar days (C3) |
| Options | **A. Freeze intervals, derived day number.** Store `(frozen_from, resumed_on)` rows. A frozen date is not a challenge day. `dayNumberOf(date)` subtracts the frozen dates before it; `endDate = startDate + 91 + closed frozen days`. **B. Explicit timeline.** Store the Arc as active segments `(first_day_number, start_date, day_count)`, or one row per challenge day. **C. Re-anchor.** On resume, move `startDate` forward by the pause. **D. A boolean and an extended end date.** |
| Evidence | C3: stored rows are keyed by date, so a mapping change needs no row rewrite. Writes are today-only, so no row can exist on a date that is frozen from tomorrow. `participatingDatesThrough` is the single source of elapsed days for streaks, summaries, insights and achievements |
| Trade-offs | **A**: existing Arcs have zero rows and behave exactly as before; the new table is additive. Every reader must go through the session's mapping (§ F1). **B**: the same information as A stored the other way round, but every existing Arc needs a backfilled segment row, a data migration over all history, and two sources of truth for dates (`start_date`/`end_date` and the segments). **C**: silently re-dates every lived day; history rows would fall outside the Arc or change day number. **D**: cannot say which dates were paused, so the paused dates would become missed days |
| Risks | A: a reader left on the old arithmetic shows a wrong day number after a freeze. Mitigated by removing the old helpers' public arithmetic and by generated-Arc tests that compare every reader |
| Recommendation | **A.** C and D are rejected: they breach "do not silently redefine historical days" and "no automatic missed days". B is rejected as a larger, riskier migration for the same result |
| Owner | YES |

**Why A preserves history.** A freeze always starts after the last date
that has any stored row (AD6). For every earlier date, the count of frozen
dates before it is unchanged, so its day number is unchanged. No stored
row is read differently and none is rewritten. Only days not yet lived
move to later dates.

### AD6. When a freeze takes effect

| | |
|---|---|
| Question | Immediately (today is paused) or at the next local day boundary? |
| Existing behavior | Not applicable. Today is the only writable day and is "open" until midnight |
| Options | (a) **Next day**: today stays a normal challenge day; the freeze starts at local midnight. (b) **Immediate**: today becomes a paused date. (c) Immediate only when today has no stored row |
| Evidence | Ledger invariant L (spec § 4.5.1): every XP row is on a participating date, and restore rejects any other. Today may already hold progress, XP, a Minimum Day row, a reflection and provisional unlocks |
| Trade-offs | (b) must delete today's rows or leave rows on a non-participating date. The first deletes progress; the second breaks restore. (c) keeps the invariant but makes Freeze a way to erase a bad day after the fact, which empties Minimum Day of meaning, and its result depends on whether anything was tapped. (a) has one rule and never touches a stored row |
| Risks | (a): a user who is unwell this morning still has today to deal with. Mitigation: the Freeze sheet says so and offers Minimum Day for today |
| Recommendation | **(a) Next day.** `frozen_from = max(today, latest date with any stored row) + 1`. The second term covers a clock that moved backwards after a later date was written. Until midnight the freeze is "scheduled" and can be cancelled, which deletes the row |
| Owner | YES |

### AD7. When a resume takes effect

| | |
|---|---|
| Question | Is the day the user resumes a challenge day? |
| Options | (a) Yes: resuming on date R makes R the next challenge day. (b) No: the Arc continues tomorrow |
| Evidence | A resume is the user's explicit act of returning. With (a) the frozen dates are `frozen_from .. R − 1`, and `resumed_on = R` |
| Trade-offs | (a) late in the evening leaves little of the day. The Resume screen says "Today becomes Day N" and offers "Not yet". Minimum Day remains available |
| Risks | None for stored data: R has no rows yet |
| Recommendation | **(a).** Resuming before the freeze has begun is "Cancel freeze" (the row is deleted; no date was paused) |
| Owner | YES |

### AD8. Freeze limits

| | |
|---|---|
| Question | Is there a maximum pause length, a number of freezes, or an automatic resume? |
| Options | (a) No cap, no automatic resume. (b) A cap per freeze or per Arc, with automatic resume at the cap. (c) A count limit |
| Evidence | Nothing runs in the background for an Arc (C3). An automatic resume would start producing missed days while the user is away, the opposite of a pause. A frozen Arc costs nothing: no reminders are planned for frozen dates |
| Trade-offs | (a) allows an Arc to stay paused indefinitely; it keeps the single unfinished slot, so a new Arc needs Resume or Restart. The next-day rule (AD6) already stops a freeze from rescuing today, and two freezes are always separated by at least one lived day |
| Risks | An Arc paused and forgotten. Mitigation: the frozen screen always shows "Paused since …" with Resume and Restart; the Arc summary and Arc History show total paused days, so the record is honest |
| Recommendation | **(a) for v1.3.** A cap is a pure rule that can be added later without a schema change; removing one after users rely on it is harder |
| Owner | YES |

### AD9. Focus Guard while frozen

| | |
|---|---|
| Question | Does a freeze pause Focus Guard? |
| Existing behavior | Focus Guard is application-level, independent of any Arc, and keeps working with no active Arc (C3). Its native worker reads only its own two tables |
| Options | (a) Independent: unchanged while frozen. (b) Suppressed while frozen |
| Evidence | (b) needs the Kotlin worker to read sessions and freeze intervals and to repeat the date rules natively, the second progress engine Phase 12A rejected for the widget |
| Trade-offs | (a): the nudge text "Time to come back to your Arc?" can appear during a pause. (b): a second implementation of freeze rules in Kotlin |
| Risks | (a) is a copy mismatch only. (b) is a correctness risk in native code |
| Recommendation | **(a) Independent.** The Freeze sheet states "Focus Guard keeps its own schedule" with a link to its settings, where it can be turned off. Hydration Coach, daily and reflection reminders do pause, because they are planned per challenge day |
| Owner | YES |

### AD10. How an Arc ended by Restart is represented

| | |
|---|---|
| Question | What does the old Arc become when the user restarts before Day 92? |
| Existing behavior | `completed` means the local date passed `endDate`; a backup rejects a completed Arc that has not ended; Summit is earned by any Arc that is over (C4) |
| Options | (a) New status **`ended`** plus a nullable `closed_on` date. (b) Keep `completed` and add `closed_on`. (c) Shorten `endDate` to the restart date. (d) Delete the old Arc |
| Evidence | (c) breaks the 92-day rule in `problemWith`. (d) is forbidden by the brief. (b) leaves the stored status saying "completed": Arc History, Insights' completed count and Summit would treat it as a finished Arc wherever a check for `closed_on` is forgotten. With (a), Dart's exhaustive `switch` on the enum (for example `AppRoutes.forSession`) turns forgotten cases into compile errors |
| Trade-offs | (a) touches every site that tests the status (24 files, § F2). (b) touches fewer, silently |
| Risks | (a): a site that uses `!= completed` to mean "unfinished" would treat an ended Arc as unfinished. Three such sites are known (C4) and listed in § F2 |
| Recommendation | **(a).** `ended` = closed by the user before its last day; read-only history like `completed`; never "Completed", never Summit. `closed_on` is the last date that counts (AD11). The planned `endDate` is kept, so the 92-day rule still holds. No DDL is needed for the status value (no `CHECK` on the column) |
| Owner | YES |

### AD11. What Restart copies

| | |
|---|---|
| Question | Is the new Arc built from the old Arc's dated revisions, or from its current effective configuration? |
| Existing behavior | "Reuse last setup" takes each habit's configuration in effect on the last day as the new baseline and copies no revision (C4) |
| Options | (a) Clone the **current effective configuration** as the new baseline. (b) Copy the baseline and every revision |
| Evidence | Revisions are dated in the old Arc's calendar (`effective_from`), and the validator requires them to lie inside their own Arc. In a new Arc they would be dates before Day 1 |
| Trade-offs | (b) preserves nothing useful: only the last revision of each habit has any effect from Day 1 on. (a) keeps the goal-change history where it belongs, with the old Arc |
| Risks | An edit made today is a revision effective tomorrow. Cloning "today's" configuration would drop it |
| Recommendation | **(a)**, using each habit's **latest** configuration, i.e. including an edit that is waiting for tomorrow (`HabitSetting.editable`). Copied per habit: id, title, type, unit, icon, order, target, minimum target, enabled (a habit that is off stays off). Not copied: revisions, progress, day modes, XP, unlocks, reflections, freezes. Habit ids are kept on purpose: built-in ids drive Hydration Coach and activity achievements, and ids are unique per session, so there is no clash |
| Owner | NO |

`closed_on` (PROPOSED): on restart date X, `closed_on` is the later of
the old Arc's latest date with any stored row and its last challenge date
before X, and never earlier than the participation start. So it is X when
something was logged today, and yesterday when nothing was. A day the
user never touched is not added as an empty last day, and no stored row
is ever left after `closed_on`, even if the clock moved backwards.

### AD12. Restart of a Seasonal Arc

| | |
|---|---|
| Question | What does Restart mean for the fixed 1 October – 31 December season? |
| Existing behavior | A seasonal Arc's Day 1 is always 1 October; joining again today would be the same late join |
| Options | (a) Offer "Start a Rolling 92-Day Arc with this setup": the season participation ends, a rolling Arc starts on Day 1 today. (b) No restart for seasonal Arcs |
| Evidence | `ArcStartRules.start` (seasonal keeps 1 October); the kind is "chosen, never copied" when reusing a setup (`startNewArc` doc) |
| Trade-offs | (a) leaves the season; the user cannot rejoin the same season with a fresh record. The sheet says so |
| Risks | A user expecting a seasonal Day 1. The wording never says "restart the season" |
| Recommendation | **(a)**, labelled as a new Rolling Arc, with the same typed confirmation |
| Owner | YES |

### AD13. Deleting the old Arc

| | |
|---|---|
| Question | Is deletion part of the restart transaction? |
| Existing behavior | Whole-Arc deletion exists for completed Arcs: one transaction, cascade, orphan check, a dialog listing what is lost (C4) |
| Options | (a) A **separate action after** a successful restart, with its own typed confirmation. (b) One combined transaction. (c) Partial deletion (keep the Arc card, erase its days) |
| Evidence | Deletion is by `session_id` with `ON DELETE CASCADE`; the new Arc is a different session, so a deletion cannot reach it. (c) would leave an Arc with no days, which the validator and the summaries cannot represent |
| Trade-offs | (a) is two steps. If the app dies between them, the old Arc is simply kept, which is the default. (b) makes one typed word authorise an irreversible loss, and a deletion failure would roll back the restart |
| Risks | A stored "delete after restart" intent would delete on a later launch without a fresh confirmation. So no intent is stored |
| Recommendation | **(a).** Scope: the whole old Arc, exactly what the existing deletion removes, plus its freeze rows. Extend the existing deletion to `ended` Arcs. Other Arcs, app settings and earlier backup files are untouched |
| Owner | YES |

### AD14. Sound engine

| | |
|---|---|
| Question | How are short sounds played? |
| Existing behavior | No audio. The repository already has a native Kotlin area with a method channel (Focus Guard) |
| Options | (a) A small native player: Android `SoundPool` with sonification audio attributes, iOS `AVAudioPlayer` with the ambient session, behind a Dart interface. (b) A Flutter audio package (`audioplayers`, `just_audio`, `flutter_soloud`, `soundpool`). (c) Flutter's `SystemSound` |
| Evidence | (c) offers only the platform click and alert. Package facts below are from general knowledge, **not verified in this phase** (no dependency was added or fetched): `just_audio` brings a media player stack sized for streaming; `audioplayers` defaults to the media stream and needs explicit audio-context configuration; `soundpool` was reported discontinued; `flutter_soloud` ships a native engine through FFI |
| Trade-offs | (a): about 100 lines per platform, no dependency, no permission, no manifest change, and exact control of the one thing that matters here: which stream and session the sound uses (AD15). It needs a JVM test and device checks. (b): less native code, but a dependency to audit, a larger APK and less control of silent-mode behaviour |
| Risks | (a): native code paths on two platforms. iOS is unreleased, so its part is a simulator smoke only |
| Recommendation | **(a).** Re-check package status at the start of 12G before any dependency is considered |
| Owner | YES (no new dependency) |

### AD15. Sound policy

| | |
|---|---|
| Question | Volume, silent mode, defaults, and a Perfect Day sound |
| Options | Stream: media volume vs the system sonification stream. Default: on vs off. Perfect Day: its own sound vs none |
| Evidence | A sound that ignores a silenced phone would be the "loud notification alarm" the brief rules out. The haptics already treat Perfect Day as its own event that replaces the habit feedback (C5) |
| Trade-offs | The sonification stream follows the ringer: silent and vibrate modes mute it. Its loudness follows the system or ring volume, which varies by manufacturer. The media stream plays in silent mode unless media volume is zero |
| Risks | **UNRESOLVED:** the exact behaviour of sonification audio in Do Not Disturb and on OxygenOS must be measured on the emulator and the OnePlus (12G, 12I). If a device mutes it when it should play, or plays it in silent mode, the stream choice is revisited before release |
| Recommendation | Sonification stream; no audio focus request, so music and podcasts keep playing; never louder than the system allows; no in-app volume control. iOS: ambient session, which respects the silent switch and mixes. **Default on** for new installs and upgrades. **One Perfect Day sound**, a longer variant of the chosen set, played instead of (never after) the habit sound, at most once per day. No sound for Minimum Day activation, level-ups or achievements |
| Owner | YES (default on; Perfect Day sound) |

### AD16. One additive migration

| | |
|---|---|
| Question | Is schema v7 needed, and how many migrations? |
| Existing behavior | Schema v6; step-by-step migrations with frozen snapshots (`schema_versions.dart`, `drift_schemas/`) |
| Options | (a) One v6 → v7 step holding everything v1.3 needs, built first. (b) A schema bump in each feature phase |
| Evidence | § G. Reorder and saved setup need nothing. Freeze needs a table, Restart a column, Sounds a table. Focus Guard's native schema gate must move from 6 to 7 in the same change (C6) |
| Trade-offs | (a) fixes the storage design before the feature phases, and gives one migration to qualify and one signed-upgrade rehearsal. (b) churns snapshots and migration tests three times |
| Risks | Forgetting the native gate would switch Focus Guard's background check off for every upgraded user, with no error. It becomes an explicit exit criterion with a JVM test |
| Recommendation | **(a)**, in a foundation phase before the features (AD18) |
| Owner | YES (v1.3.0 becomes a migration release) |

### AD17. Backup format 4

| | |
|---|---|
| Question | Can format 3 carry the new state? |
| Existing behavior | Strict codec; unknown fields, values and versions are rejected (C6) |
| Options | (a) Format 4, written always; read 1–4. (b) Write format 3 when no new construct is used, else 4. (c) Keep format 3 and leave freezes, ended Arcs and sound settings out |
| Evidence | (c) cannot work: an ended Arc is not expressible in format 3 (no `ended` status; a `completed` Arc must have ended), and a frozen Arc's end date breaks the 92-day rule. Dropping freeze rows on restore would turn paused dates into missed days |
| Trade-offs | (b) keeps some v1.3 backups readable by v1.2.0 at the price of two writers and a file whose format depends on its content. (a) is what v1.2 did for format 3 |
| Risks | A v1.3 backup cannot be restored into v1.2.0. v1.2.0 answers "Unsupported backup formatVersion" and changes nothing (CONFIRMED in `BackupCodec.decode`) |
| Recommendation | **(a).** Details in § H |
| Owner | YES |

### AD18. Phase order

| | |
|---|---|
| Question | Can Weekly Review and Calendar be built before Freeze exists? |
| Existing behavior | Their approved rules compute dates as `s.startDate.addDays(d − 1)` and assume `s.lengthInDays = 92` (spec § 3.2) |
| Options | (a) The owner's order: 12B Review, 12C Calendar, 12D, 12E Freeze, … (b) **Foundation first**: split 12E into 12E1 (schema v7, format 4, the session's day ↔ date mapping, every existing reader moved onto it, no user-visible change) and 12E2 (Freeze UI and service); run 12E1 before 12B. (c) Stage the release: v1.3.0 with Review, Calendar, reorder and saved setup (no migration), v1.4.0 with Freeze, Restart and Sounds |
| Evidence | With (a), Review and Calendar are written and tested on arithmetic that 12E then replaces underneath them; their paused-week and ended-Arc states (spec § 12) could not be tested when built |
| Trade-offs | (b) makes the first implementation phase a migration with no visible feature. In return every later phase builds on the final model once. (c) lowers release risk but delays three of the five features |
| Risks | (b): the storage design of Restart and Sounds is fixed before their phases; this addendum is that design |
| Recommendation | **(b)** as the plan for a single v1.3.0, keeping the owner's phase letters. **(c)** is the documented fallback if 12E1 or 12E2 slips or fails qualification. No feature is removed from the plan |
| Owner | YES |

## F. Freeze: impact on every component

### F1. The session's day ↔ date mapping (PROPOSED)

`WinterArcSession` gains `freezes` (ordered, non-overlapping intervals)
and `closedOn`. All day arithmetic moves behind these members. Their
exact rules are in
[ARC_CONTROL_SPEC.md § 5](ARC_CONTROL_SPEC.md#5-freeze-and-resume-rolling-arcs-only).

| Member | Today | With freeze intervals |
|---|---|---|
| `WinterArcRules.lengthInDays` | 92 | unchanged: the number of **challenge days** |
| `lengthInDays` (getter) | `startDate.daysUntil(endDate) + 1` | callers that mean "92" use the constant; the calendar span gets its own name |
| `isFrozenOn(date)` | – | inside any interval `[frozenFrom, resumedOn)`; open intervals have no end |
| `isParticipatingOn(date)` | joined ≤ date ≤ end | the same, and not frozen, and not after `closedOn` |
| `dayNumberOf(date)` | offset + 1 | offset + 1 − frozen dates before `date` |
| `dateOfDay(n)` | (callers add days) | the inverse; unknown for days beyond an open freeze |
| `participatingDatesThrough(today)` | contiguous range | the same range without frozen dates, cut at `closedOn` |
| `endDate` (stored) | `startDate + 91` | `startDate + 91 + closed frozen days`, extended in the resume transaction |
| `isOverOn(date)` | `date > endDate` | the same, and never while a freeze is open |
| `positionOn(date)` | from the offset | from `dayNumberOf` for challenge dates; a frozen date is its own position |

With no freeze rows and no `closedOn`, each member returns what it returns
today. That is the regression guarantee for every existing Arc.

Readers to move onto the mapping (from the call-site inventory, C3):

| Component | Source | Change |
|---|---|---|
| `WinterArcRules` | `winter_arc_session.dart` | `problemWith`: a rolling Arc's end is `start + 91 + closed frozen days`; freezes only on rolling, started Arcs; `closedOn` rules |
| `ArcLifecycleService` | `arc_lifecycle_service.dart` | Close-out uses the freeze-aware `isOverOn`: a frozen Arc never completes. Leaves `ended` Arcs untouched |
| `CurrentArcService` | `current_arc_service.dart` | `latestCompleted` and `home` consider finished Arcs (`completed` or `ended`); `requireWritable` reports an ended Arc as closed |
| `DayRules`, XP | `day_rules.dart`, `xp.dart` | **None.** They settle one date; writes are refused on a frozen date by `_trackableSession`. No XP for freezing or resuming |
| `HabitTrackingService` | `habit_tracking_service.dart` | `_trackableSession` unchanged (uses `isParticipatingOn`). `_nextChallengeDay` stays "tomorrow" for goal edits: a revision dated on a later-frozen date still applies from the first challenge day on or after it (`HabitHistory.configOn`). Habit editing is read-only while frozen |
| `StreakRules`, `ArcHistory` | `streak_rules.dart`, `arc_history.dart` | `elapsedDates` excludes frozen dates, so streaks continue across a pause unchanged. `journey()` iterates challenge days through `dateOfDay` |
| Achievements | `achievement_rules.dart` | `_participatedMilestone` uses `dateOfDay(day)` instead of `startDate.addDays(day − 1)`. Summit stays "the Arc ran to its close" and is never earned by an `ended` Arc. Stored unlocks are never re-dated |
| Journey | `journey_day.dart`, `journey_overview.dart`, `journey_path.dart` | 92 challenge days as before; a pause marker between the days around a freeze; a ninth state `notReached` for an ended Arc's unlived days (spec § 12.4) |
| Insights | `insight_rules.dart` | Elapsed days come from the mapping. An `ended` Arc must not be taken for the active Arc (C4) and is not counted as completed |
| Arc History, Summary | `arc_history_service.dart`, `arc_summary.dart`, `arc_history_tile.dart`, `summary_screen.dart` | `totalDays` is the constant 92. Tiles show "Ended early · Day N" and total paused days |
| Weekly Review, Calendar | spec § 12 | Built on `dateOfDay`; paused and ended states |
| Backup | `backup_codec.dart`, `backup_validator.dart`, `drift_backup_store.dart` | § H |
| Migration | `app_database.dart` | § G |
| Reminders | `reminder_plan.dart` | Daily and reflection reminders are planned for challenge dates only and name the freeze-aware day number. A reconcile runs right after freeze, cancel and resume |
| Hydration Coach | `hydration_planner.dart` | **None**: it already asks `isParticipatingOn(date)` |
| Focus Guard | `focusguard/*.kt` | Behaviour unchanged (AD9). The schema gate moves to 7 (AD16) |
| Labels, share cards, scene | `arc_labels.dart`, `share_card_data.dart`, `scene_progress.dart`, `today_hero.dart` | Day number and progress from the mapping; an open freeze has no end date to print |

### F2. Sites that test the status

24 files reference `WinterArcStatus` values. For `ended` each one is
either an exhaustive `switch` (a compile error until handled) or one of
these comparisons, which must be reviewed by hand in 12E1:

| Site | Today | Needed |
|---|---|---|
| `BackupValidator.validate` | `status != completed` counts as unfinished | unfinished = `setup` or `active` |
| `BackupSummary.of` | the same | the same |
| `InsightRules.compute` | not `completed` ⇒ the active Arc | only `active` is active |
| `DriftWinterArcRepository.latestCompletedSession` | newest `completed` | newest finished (`completed` or `ended`) |
| `WinterArcService._reusable` | the latest completed Arc | the latest finished Arc |
| `WinterArcService.deleteCompletedArc`, `deleteSession` | only `completed` | `completed` or `ended`; orphan check also covers `arc_freezes` |
| `SummaryScreen` | Delete for `completed` | Delete for finished Arcs |

### F3. Edge cases

| Case | Result |
|---|---|
| Freeze on Day 1 | Allowed. Day 1 is lived today; the freeze starts tomorrow |
| Freeze on Day 91 | Allowed. Day 92 is lived on the resume date |
| Freeze on Day 92 | Not offered: no challenge day is left to pause |
| Freeze and cancel on the same date | The row is deleted. Nothing was paused |
| Resume on the first frozen date | `resumedOn == frozenFrom`: an empty interval, stored as a deleted row |
| Several freezes | Each starts after a lived day. Day numbers subtract all earlier intervals |
| Midnight with the app open | The existing day-change ticker refreshes; a scheduled freeze becomes frozen with no write |
| App closed, phone rebooted | The state is derived from stored dates and the clock. Nothing is scheduled for a frozen date, so there is nothing to recover |
| Time zone moves the date back before `frozenFrom` | The Arc is running again on that date (it is a challenge date); it is frozen again when the date returns |
| Date moves back into a closed interval | That date is paused: read-only, "continues on <resume date>" |
| Daylight saving | No effect: `LocalDate` arithmetic |
| Long pause | No effect on stored data. The end date is fixed only at resume |
| Restart while frozen | The old Arc ends on its last lived day; the open freeze row is removed |
| Seasonal Arc | No freeze: not offered, refused by the service, rejected by restore |

## G. Schema v7 (PROPOSED, additive)

| Feature | Existing state used | New state | Migration |
|---|---|---|---|
| Reorder | `habits.sort_order` | none | none |
| Saved setup | `winter_arc_sessions` (`setup`), `habits` | none | none |
| Freeze | `winter_arc_sessions.end_date` | table `arc_freezes` | `CREATE TABLE` |
| Restart | `winter_arc_sessions.status` | status value `ended`; column `closed_on` | `ALTER TABLE ADD COLUMN` |
| Sounds | none | table `feedback_preferences` | `CREATE TABLE` |

```
arc_freezes
  session_id    INTEGER NOT NULL REFERENCES winter_arc_sessions(id) ON DELETE CASCADE
  frozen_from   TEXT    NOT NULL        -- first paused local date
  resumed_on    TEXT    NULL            -- first challenge date after the pause; NULL while open
  requested_at  DATETIME NOT NULL
  resumed_at    DATETIME NULL
  PRIMARY KEY (session_id, frozen_from)
  CHECK (resumed_on IS NULL OR resumed_on > frozen_from)
  UNIQUE INDEX one_open_freeze ON arc_freezes(session_id) WHERE resumed_on IS NULL

winter_arc_sessions
  + closed_on   TEXT NULL               -- last counted date of an 'ended' Arc

feedback_preferences                    -- single row, id = 1, absent until first changed
  id             INTEGER PRIMARY KEY CHECK (id = 1)
  sounds_enabled INTEGER NOT NULL       -- boolean
  sound_theme    TEXT NOT NULL CHECK (sound_theme IN ('iceCrystal','summitSpark','warmEmber'))
  updated_at     DATETIME NOT NULL
```

- **Non-destructive.** The step creates two empty tables and adds one
  nullable column. No existing row is read, rewritten or deleted. Existing
  Arcs have no freeze rows and a null `closed_on`, so they behave as in
  v1.2.0.
- `single_open_session` is unchanged. An `ended` Arc is outside it, which
  is what lets a new Arc start in the same transaction.
- **Native gate.** `FocusGuardStore.SCHEMA_VERSION` becomes 7 in the same
  change, with `FocusGuardStoreTest` and `DriftFixture.kt` updated. The
  Focus Guard tables themselves do not change.
- **Rollback.** There is no in-place downgrade: Android refuses a lower
  version code, and v1.2.0 does not know schema v7. The way back is a
  format ≤ 3 backup made before upgrading. The 12I rehearsal exports one
  first.
- New snapshot `drift_schemas/drift_schema_v7.json`, `migration_v7_test`,
  and CI's migration step extended to v7 (all in 12E1).

## H. Backup format 4 (PROPOSED)

| | |
|---|---|
| Writes | format 4 only |
| Reads | 1, 2, 3 and 4. Older files keep their own rules and are read into the current model with no freezes, no `closedOn` and no sound settings |
| New in an Arc | `status: "ended"`; `closedOn`; `freezes: [{ frozenFrom, resumedOn \| null, requestedAt, resumedAt \| null }]` |
| New in the data | `feedback: { soundsEnabled, soundTheme } \| null` |
| v1.2.0 and earlier | reject format 4 before reading it ("Unsupported backup formatVersion"), changing nothing |

Validation added for format 4 (positions and rule names only in errors,
as today):

- Freezes: rolling, started Arcs only; ordered and non-overlapping;
  `frozenFrom` after the participation start and not after `endDate`;
  `resumedOn > frozenFrom`; at most one open freeze, only on an `active`
  Arc; `frozenFrom` no later than the day after the export, `resumedOn`
  not after the export.
- Rolling end date: `endDate == startDate + 91 + closed frozen days`.
- No dated row (progress, mode, XP, unlock, reflection) on a frozen date.
  This follows from the existing "date outside the arc" check once
  `isParticipatingOn` excludes frozen dates.
- Revisions: `effectiveFrom` must lie within the Arc's calendar span. It
  may be a frozen date (an edit made the day before a freeze).
- `ended`: `closedOn` present, between the participation start and
  `endDate`, not after the export; no row after `closedOn`; no open
  freeze. `closedOn` is absent for every other status.
- Unfinished Arcs are `setup` or `active` (F2).

Restore:

- One transaction, as today (`DriftBackupStore.replaceAll`), now also
  replacing `arc_freezes`. An interrupted restore leaves the previous data
  intact.
- Reminders and Focus Guard are restored off, as today.
- The sound setting is restored as stored. A format 1–3 file has none, so
  the device's current setting is kept. A restore never plays a sound.
- A restored frozen Arc is frozen; a restored scheduled freeze is
  scheduled. Both are plain dates.
- A restored setup is the saved setup; the hub opens on it.

## I. Impact on the approved Arc Momentum design

The full rule changes are in
[ARC_MOMENTUM_SPEC.md § 12](ARC_MOMENTUM_SPEC.md#12-lifecycle-addendum-freeze-and-restart).
In short:

| Question (brief § 12) | Answer |
|---|---|
| What is an Arc week after a pause? | Still Arc days: Week `w` is Days `7(w−1)+1 .. 7w`, Week 13 is Days 85–92. A pause moves dates, never day numbers |
| Do 92 active days still form 13 weeks? | Yes, always |
| How is a challenge day mapped to a date? | `s.dateOfDay(d)` (F1), not `startDate + (d − 1)` |
| What appears for frozen dates? | They are not days of the Arc: no cell, no count. The calendar shows one "Paused" row between the days around the pause; a week heading names the pause |
| How are frozen dates kept out of metrics? | They are never in `elapsedDates`, so never in `N`, `H`, `C`, `F`, `P` or XP |
| An already-final week? | Never changes. A freeze starts after today, and a final week ended before today |
| A resumed week? | Its remaining days continue from the resume date. While frozen, the week is `paused`: totals so far, no "Today so far" block |
| Week 13? | Unchanged: Days 85–92. A pause inside it only moves its dates |
| Does a restarted Arc get new weeks? | Yes. It is a new session with its own Weeks 1–13 |
| Reviews of the old Arc? | Kept and read-only at `/arc/:id/review`: the weeks up to `closedOn`; later weeks are "not reached" |
| Deletion and Insights? | Insights are derived, so a deleted Arc's days leave every total. Nothing else changes |
| Ended vs completed? | `ended` is its own status: "Ended early · Day N", no Summit, not counted in Insights' completed Arcs |

The F1 XP ledger correction is preserved: the four-group split of spec
§ 4.5.1 is unchanged, and group D ("other XP") stays 0 because no XP row
can exist on a frozen date or after `closedOn`. The old equation
`Σ_w X(w) + xpByDate[T] = totalXp` is not reintroduced.

## J. Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | A reader left on `startDate` arithmetic shows wrong days after a freeze | medium / high | F1 inventory; one mapping on the session; a generated-Arc test comparing Today, Journey, Calendar, Review, Insights, reminders and achievements for the same dates |
| R2 | Focus Guard silently off after the upgrade (schema gate) | high if forgotten / high | 12E1 exit criterion; JVM test; emulator check of a natural run after the upgrade |
| R3 | Freeze used to dodge hard days | medium / medium | Next-day rule; a lived day between freezes; paused days shown in the record |
| R4 | History changed by a freeze | low / critical | No stored row is rewritten; byte-identical table tests around freeze, cancel and resume |
| R5 | Restart loses or duplicates data | low / critical | One transaction; the old Arc is only updated in two columns; tests that every old row is identical and the new ledger is empty |
| R6 | An `ended` Arc shown as completed, or earning Summit | medium / high | Separate status; F2 list; tests on History, Insights and achievements |
| R7 | Deletion removes more than the old Arc | low / critical | Deletion by session id; test that every other table row is identical; no stored deletion intent |
| R8 | v1.3 backups unreadable by v1.2 | certain / low | Documented; v1.2 refuses safely; release notes |
| R9 | Sound plays on a silenced phone, or not at all | medium / medium | Sonification stream; device matrix in 12G and 12I; stream revisited if a device disagrees |
| R10 | Sound spam | low / medium | Transition-only trigger; throttle; no queueing |
| R11 | Scope of one release | medium / high | Foundation first (AD18); staged fallback kept ready; a gate after every phase |
| R12 | Saved setup started by accident | low / medium | Start only from the confirm screen |
| R13 | Reorder leaves duplicate orders | low / medium | One transaction with an id-set check; export validation already rejects duplicates |
| R14 | Layout at 2× text on the new screens | medium / medium | Wireframe rules; layout sweep; emulator check at 2× / 360 dp |

## K. Phase dependencies

```
12A Addendum ─Gate A2─► 12E1 ─► 12B ─► 12C ─► 12D ─► 12E2 ─► 12F ─► 12G ─► 12H ─► 12I ─Gate P─► publish
                         │       ▲      ▲             ▲       ▲      ▲
                         └───────┴──────┴─────────────┴───────┴──────┘
                           schema v7, format 4, day ↔ date mapping
```

- 12B and 12C depend on 12E1's mapping (and 12C on 12B's `ArcWeeks`).
- 12D depends on nothing in 12E1 and may run at any point after Gate A2.
- 12E2 depends on 12E1. 12F depends on 12E1 (`ended`, `closed_on`) and on
  12D's review and confirm screens for its wording, and must handle a
  frozen Arc, so it follows 12E2.
- 12G depends on 12E1 only (the settings table).
- 12H and 12I come last. Details and gates:
  [V1_3_ROADMAP.md](V1_3_ROADMAP.md#phase-plan).

## L. Qualification plan

Layers: **U** pure Dart, **R** repository / database (in-memory Drift or
restored fixtures), **W** widget, **I** integration (`test/integration/`),
**J** Android JVM, **E** emulator, **P** physical device (12I only, after
owner authorization). The whole existing suite stays green and unweakened;
no historical test is edited to make room for new semantics, except the
constants that state the schema and format versions.

### L1. Foundation (12E1)

| Case | Layer |
|---|---|
| With no freeze rows, every mapping member equals the v1.2 arithmetic for generated Arcs (rolling, seasonal, late join) and every date | U (property) |
| Migration v6 → v7 on every earlier fixture: all v6 rows identical; new tables empty; `closed_on` null | R |
| Format 4 round trip; formats 1, 2, 3 still restore; a format-4 file is rejected by the format-3 rules | R |
| Focus Guard store accepts schema 7 and refuses 6 and 8 | J |
| A natural Focus Guard run after an in-place upgrade | E |

### L2. Habit ordering and saved setup (12D)

| Case | Layer |
|---|---|
| Reorder writes `0..n−1`; ids, targets, enabled, titles unchanged; a wrong id set writes nothing | U + R |
| Order after save, after reopening, after start, after restart, after a format-4 restore | R + W |
| Disabled and custom habits move like any other; 12 habits; reorder then edit; reorder then add; reorder then remove | W |
| Move up / down from the menu and from screen-reader actions; first and last items | W |
| App restart and process death after each kind of edit: the setup is as last written | R + I |
| Empty setup: saved, reopened, cannot start; hub shows "Add a habit to start" | W |
| Custom habits and custom goals survive save, reopen, start | R |
| Saving twice; editing after saving | W |
| Starting days later: Day 1 is the confirmation date; the days between are not days of the Arc | U + R |
| Seasonal: preseason setup cannot start; in season starts on the season day; ended season can only be cancelled; the confirm screen cannot bypass any of these | U + W |
| Midnight on the confirm screen: the shown Day 1 date updates | W |
| Backup with a setup; restore opens the hub | R + W |
| Cancel on the confirm screen starts nothing (session row identical) | R |

### L3. Freeze (12E2)

| Case | Layer |
|---|---|
| Freeze on Day 1, 25, 91; not offered on Day 92; never on a seasonal Arc | U + W |
| Day numbers, end date and `dateOfDay` after one and after several intervals | U (property) |
| Same-day freeze and cancel; resume on the first frozen date | U + R |
| Midnight rollover: scheduled → frozen with no write; app open and app closed | W + E |
| Long freeze (400 days); resume gives the right day and end date | U |
| Time-zone change before `frozenFrom`, into a closed interval, and across a resume | U + R |
| App kill and device reboot while frozen and while scheduled | E |
| Streaks: a streak before the pause continues after it; no miss is created | U |
| XP: no ledger row is written, changed or removed by freeze, cancel or resume; none can be written on a frozen date | R |
| Every table except `arc_freezes` and the session's `end_date` is byte-identical around freeze and resume | R |
| Weekly Review: paused week, resumed week, Week 13 with a pause, identities of spec § 4.5 with frozen dates | U (property) |
| Calendar: 92 cells, pause row, same state as Journey for every day | U + W |
| Notifications: nothing pending for a frozen date after freeze; re-planned after resume; Hydration follows | U + E |
| Achievements: milestones use the mapped date; no unlock is re-dated or lost | U + R |
| Backup with an open, a scheduled and several closed freezes; restore | R |
| Freeze `clock rollback` rule: `frozenFrom` is after the latest stored row | R |

### L4. Restart and deletion (12F)

| Case | Layer |
|---|---|
| Same setup: ids, titles, types, units, icons, order, enabled state | U + R |
| Custom habits; edited goals (including an edit waiting for tomorrow) become the baseline; no revision is copied | U + R |
| Fresh Day 1 today; 0 XP; level 1; no progress, modes, unlocks, reflections | R |
| No duplicated XP: the old ledger is identical row for row; the new one is empty | R |
| Old Arc: `ended`, `closed_on` per AD11, shown as "Ended early", no Summit, not "completed" in Insights | U + W |
| Active rolling, frozen rolling, scheduled freeze, seasonal, late seasonal join, Minimum Day history, reminders on | U + R + W |
| Typed confirmation: empty, "restart", "RESTAR", " RESTART " and "RESTART"; the button state for each | W |
| Cancel and Back at every step write nothing | R |
| Database failure inside the transaction: nothing changed | R |
| Restore after restart: both Arcs as stored | R |
| Insights and achievements after a restart | U |
| Optional deletion: needs its own typed word; removes only the old Arc; every other row identical; failure keeps both Arcs | R + W |
| Process death between restart and deletion: the old Arc is kept | I |

### L5. Sounds (12G)

| Case | Layer |
|---|---|
| Binary completion; count reaching its target (silent before it); duration reaching its target; clock time at or before the goal (silent after it) | W with a fake player |
| Reversed completion is silent; restored completion sounds again, throttled | W |
| Perfect Day: one Perfect Day sound, no habit sound | W |
| Minimum Day activation is silent; completing a Minimum Day plays the habit sound | W |
| Toggle off: the player is never called | W |
| Rapid updates: at most one play per throttle window; nothing queued | U + W |
| Restore, launch, opening screens, midnight, achievement backfill: no play | W + I |
| Offline: no network use (`test/app/network_boundary_test.dart` unchanged) | I |
| Native player: loads, plays, skips when not loaded, releases | J |
| Ringer silent, vibrate, Do Not Disturb, music playing, TalkBack on | E, then P in 12I |
| Setting survives restart and a format-4 restore | R |

### L6. Integration and release (12H, 12I)

As in [PHASE_12A.md § L5–L6](PHASE_12A.md#l5-release-regression-12e-12f),
plus: the combined flow (saved setup → start → review → freeze → resume →
restart → delete), the layout sweep over every new screen, a signed
v1.2.0 → v1.3.0 rehearsal on a disposable AVD with a **real v6 → v7
migration** and every v6 row compared, and the physical OnePlus upgrade
only after explicit owner authorization.

## M. Owner decisions (Gate A2)

| # | Decision | Recommendation |
|---|---|---|
| O1 | Reordering in setup only (AD2) | Yes |
| O2 | One saved setup; changes saved as made, plus "Save for Later" (AD3) | Yes |
| O3 | Freeze stored as intervals with a derived day number (AD5) | Yes |
| O4 | A freeze starts at the next local midnight (AD6) | Yes |
| O5 | Resuming makes today the next challenge day (AD7) | Yes |
| O6 | No maximum pause and no automatic resume in v1.3 (AD8) | Yes |
| O7 | Focus Guard keeps running during a freeze (AD9) | Yes |
| O8 | A restarted Arc becomes `ended`, never `completed` (AD10) | Yes |
| O9 | A Seasonal Arc "restarts" as a new Rolling Arc (AD12) | Yes |
| O10 | Deleting the old Arc is a separate step with its own typed word, and removes the whole Arc including its reflections (AD13) | Yes |
| O11 | Should the existing "Delete Arc" for completed Arcs also require the typed word? | Yes, for one consistent rule |
| O12 | Native sound player, no new dependency (AD14) | Yes |
| O13 | Sounds on by default; one Perfect Day sound (AD15) | Yes |
| O14 | v1.3.0 becomes a migration release: schema v7, backup format 4 (AD16, AD17) | Yes |
| O15 | Phase order with the foundation first, or the staged fallback (AD18) | Foundation first, one release |

**Unresolved until measured on a device** (not blockers for this phase):
sonification-stream behaviour in Do Not Disturb and on OxygenOS; TalkBack
with a sound playing; drag gestures and TalkBack reordering on a real
phone; the wording of the three sound names.

## N. Phase 12A Addendum qualification results

| Check | Result |
|---|---|
| Baseline: `origin/main` = `64d77e0`; no Phase 12B work exists | PASS |
| Clean worktree and branch from the verified commit; primary checkout and other worktrees untouched | PASS |
| Every source path cited in the changed documents exists at `64d77e0` (script), and every cited class, method and quoted comment was searched for in the source. The one path that doesn't exist is the future `drift_schemas/drift_schema_v7.json` | PASS |
| Relative Markdown links and anchors in the changed documents resolve (script) | PASS |
| Stop conditions of the brief | none triggered |
| `git diff --check` | PASS |
| Changed files: only `docs/PHASE_12A_ADDENDUM.md`, `docs/ARC_CONTROL_SPEC.md`, `docs/V1_3_ROADMAP.md`, `docs/ARC_MOMENTUM_SPEC.md`, `PROJECT_STATE.md` | PASS |
| No file under `lib/`, `android/`, `ios/`, `test/`, `integration_test/`, no `pubspec.*`, `.github/`, `tool/` changed; version `1.2.0+3` | PASS |
| Physical phone, emulator, APK, audio assets | not used / not built / not generated |
| GitHub Actions on the PR's final head | see the PR |

Not run, on purpose: `flutter test` and platform builds locally. This
change is documentation only, and CI runs them on the PR.

Source claims in this addendum were read from the files named. Claims
about Flutter SDK widgets, Android audio streams and audio packages are
from general knowledge and are marked PROPOSED or UNRESOLVED; none was
tested in this phase.
