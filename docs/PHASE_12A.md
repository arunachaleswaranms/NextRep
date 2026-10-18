# Phase 12A: v1.3.0 Arc Momentum planning and architecture

## A. Objective and boundary

Design NextRep v1.3.0 around **Arc Momentum**: help users see how they are
doing, where they are struggling and what to focus on next, using only data
already on the device.

This is a **documentation-only** planning phase. It adds three documents
and a PROJECT_STATE entry. It changes no file under `lib/`, `android/`,
`ios/`, `test/`, `integration_test/`, no `pubspec.*`, workflow, release
tool, schema, backup format, version or signing configuration. No physical
device or emulator was used, and no APK was built, installed or published.

| Document | Purpose |
|---|---|
| [ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md) | User stories, week rules, metric formulas, worked examples, summary rules, calendar states and layout, accessibility, data flow, performance, acceptance criteria |
| [V1_3_ROADMAP.md](V1_3_ROADMAP.md) | Scope, Phases 12B–12F, dependencies, approval gates, release safety |
| This file | Baseline, architecture inventory, invariants, decisions with evidence, data-model findings, feasibility verdicts, risks, test plan, Phase 12A checks |

Labels: **CONFIRMED** (verified in the source), **PROPOSED** (a design
decision), **UNRESOLVED** (needs an owner decision or later qualification).

**Summary of outcomes**

| Item | Result |
|---|---|
| Weekly Arc Review (guaranteed) | Specified. Derived from existing history. |
| Arc Consistency Calendar (guaranteed) | Specified. A second view of Journey's existing data. |
| Week model | **Arc-relative weeks**: 13 weeks, Week 13 = Days 85–92 |
| Database migration for v1.3.0 | **NO** |
| Backup-format change for v1.3.0 | **NO** |
| Weekly Focus (conditional) | **DEFER** |
| Android home-screen widget (conditional) | **DEFER** |

## B. Verified baseline

Checked on 18 October 2026, before any change.

| | |
|---|---|
| `origin/main` | `28db2af19cabf29acd3dbc7a8ef3cace77ecbe70`, "docs: record NextRep v1.2.0 publication (#21)", matching the expected HEAD |
| Tag `v1.2.0` | annotated tag object `fe53eae` → commit `8ab0c43` (PR #20), unchanged |
| GitHub Release v1.2.0 | "NextRep v1.2.0": not draft, not prerelease, published 2026-10-18T06:28:01Z; assets `NextRep-v1.2.0-android.apk` (66,360,265 bytes) and `.sha256` (93 bytes) |
| PRs | #20 (Phase 11F) merged 2026-10-18 04:16 UTC; #21 (publication record) merged 2026-10-18 07:09 UTC |
| Version (source) | `1.2.0+3`, unchanged |
| Database schema | v6 (`AppDatabase.schemaVersion`), unchanged |
| Backup | write format 3, read 1 / 2 / 3 (`BackupFormat`), unchanged |
| Primary checkout | `~/labs/NextRep` on `phase/11b-smart-hydration` at `15392ce`, clean; **not touched** |
| Other worktrees | `NextRep-phase11c` … `NextRep-phase11f`, **not touched** |
| Planning worktree | `~/labs/NextRep-12A`, branch `phase/12a-v1.3-arc-momentum-planning`, created from `28db2af` |
| Post-publication update check on the phone | owner-reported as completed after Phase 11F. Treated as **owner-reported, not instrumented**. The Phase 11F record (NOT RUN by the agent on 18 October) is unchanged |

## C. Architecture inventory (CONFIRMED)

Every path below exists at `28db2af` (checked by script, § N).

### C1. Domain and time

| Concern | Source | Responsibility |
|---|---|---|
| Arc session model | `lib/domain/winter_arc/winter_arc_session.dart` | `WinterArcSession`, `WinterArcRules` (92 days, validity), `WinterArcStatus`, `ArcDayPosition`; `isParticipatingOn`, `isBeforeJoining`, `participatingDatesThrough`, `dayNumberOf`, `joinDayNumber` |
| Rolling vs seasonal | `lib/domain/winter_arc/arc_kind.dart` | `ArcKind`, `SeasonalWinterRules` (1 Oct – 31 Dec, preseason in September), `SeasonAvailability` |
| Rolling date handling | `WinterArcRules.endDateFor` in `winter_arc_session.dart` | the end is the start + 91 days; participation = start date |
| Seasonal date handling | `SeasonalWinterRules` (`arc_kind.dart`) and `isBeforeJoining` | fixed numbering from 1 Oct; neutral pre-join days |
| Arc lifecycle | `lib/domain/winter_arc/arc_lifecycle_service.dart` | closes out an active Arc on the first local date after Day 92, at entry points |
| Current-Arc resolution | `lib/domain/winter_arc/current_arc_service.dart` | home / active / latest completed; `requireStarted(id)` |
| Habit definitions | `lib/domain/habit/habit.dart` | `Habit`, `HabitType` (`binary`, `count`, `duration`, `timeBefore`) and `isCompletedBy`, the single completion authority |
| Habit revisions and goal changes | `lib/domain/habit/habit_config.dart` | `HabitConfig`, `HabitRevision`, `HabitHistory.configOn` / `planFor` (latest revision effective on or before the date) |
| Goal-edit rules | `lib/domain/habit/habit_edit.dart` | target limits; the last enabled habit can't be disabled |
| Max 12 habits | `lib/domain/habit/setup_habit_rules.dart` | `SetupHabitRules.maxHabits = 12` |
| Sleep Before Target | `lib/domain/habit/night_time.dart`, `HabitType.timeBefore` | night-time values; the minimum equals the target |
| Daily progress | `lib/domain/progress/daily_habit_progress.dart` | stored `completed` flag, decided against that day's effective target |
| Progress actions | `lib/domain/progress/habit_progress_rules.dart` | what an action does to a habit's value |
| Day record and completion | `lib/domain/progress/day_record.dart` | `DayRecord` (`isPerfect`, `isMinimumComplete`, `hasProgress`), `DayCompletion` |
| Minimum Day | `lib/domain/progress/day_mode.dart` | `DayMode.normal` / `minimum`; reversible only while today |
| Perfect Day, XP settlement | `lib/domain/progress/day_rules.dart` | `DayRules.settle` keeps three invariants: completion, one habit award per completed habit, one Perfect Day award iff a normal day is all complete |
| XP amounts and keys | `lib/domain/xp/xp.dart` | `XpRules.habitCompletion = 15`, `perfectDayBonus = 30`, idempotency keys |
| Levels | `lib/domain/xp/level_rules.dart` | levels derived from total XP, never stored |
| Streaks | `lib/domain/progress/streak_rules.dart` | `StreakMark` (`hit` / `miss` / `skip` / `pending`), `StreakRules.compute` |
| Derived Arc history | `lib/domain/progress/arc_history.dart` | `ArcRecords` (snapshot), `ArcHistory` (`elapsedDates`, `recordOn` with cache, `habitStreak`, `perfectDays`, `journey()`) |
| Today read model | `lib/domain/progress/day_summary.dart` | `DaySummary`, `canSwitchToMinimum`, `canReturnToFullTargets` |
| Arc summary | `lib/domain/progress/arc_summary.dart` | `ArcSummary` (`consistencyPercent` = full days / elapsed days, strongest habit) |
| Tracking use cases | `lib/domain/progress/habit_tracking_service.dart` | every write via `commitDay`; reads `history()`, `historyFor(id)`, `journey()`, `journeyFor(id)` |
| Progress persistence boundary | `lib/domain/progress/progress_repository.dart` | `loadArc`, `commitDay`, `progressOn`, `totalXp` |
| Achievements (32) | `lib/domain/achievement/achievement_catalog.dart`, `achievement_rules.dart`, `achievement_service.dart`, `achievement.dart` | catalog in code; unlocks derived, then reconciled and persisted |
| Journey | `lib/domain/journey/journey_day.dart`, `journey_overview.dart`, `arc_milestones.dart` | `JourneyDayState` (8 non-overlapping states), `JourneyRules.stateOf`, `JourneyChapter`, `ArcMilestone` |
| Insights | `lib/domain/insights/insight_rules.dart`, `insight_service.dart`, `insight_snapshot.dart` | cross-Arc consistency, per-habit completion, moods; pure rules, computed on demand |
| Journal | `lib/domain/reflection/daily_reflection.dart`, `reflection_service.dart`, `reflection_repository.dart` | private reflections; `moodsFor` returns dates and moods only |
| Arc History | `lib/domain/history/arc_history_service.dart` | `ArcHistoryCard`, one card loaded per Arc on demand |
| Local date | `lib/core/time/local_date.dart` | calendar date with UTC-midnight arithmetic (immune to DST) |
| Clock | `lib/core/time/clock.dart` | injectable `Clock`, `today()` |

### C2. Data, persistence and backup

| Concern | Source | Responsibility |
|---|---|---|
| Drift database | `lib/core/database/app_database.dart` | `schemaVersion => 6`, step-by-step migrations |
| Tables | `lib/core/database/tables.dart` | sessions, habits, progress, `xp_transactions`, `habit_revisions`, `day_modes`, unlocks, reflections, reminder and Focus Guard preferences |
| Migration snapshots | `lib/core/database/schema_versions.dart`, `drift_schemas/` | generated per-version schemas |
| Progress repository | `lib/data/drift_progress_repository.dart` | `loadArc`: one transaction, 5 SELECTs (progress, modes, XP grouped by date, habits, revisions) |
| Habit loading | `lib/data/habit_mapping.dart` | `loadHabitHistory` (habits + revisions, 2 SELECTs) |
| Backup encoding | `lib/domain/backup/backup_codec.dart`, `backup_document.dart` | format dispatch; write 3, read 1 / 2 / 3; XP amounts 1..1000 |
| Backup validation | `lib/domain/backup/backup_validator.dart` | session rules, dates, keys, uniqueness. **Does not** check that XP rows match completion |
| Backup store and restore | `lib/data/drift_backup_store.dart` (`replaceAll`), `lib/domain/backup/backup_service.dart` | replace-everything restore in one transaction |

### C3. App, navigation and presentation

| Concern | Source | Responsibility |
|---|---|---|
| Composition and providers | `lib/app/dependencies.dart` | Riverpod wiring, `ambientMotionProvider` |
| Navigation | `lib/app/router/app_router.dart`, `lib/features/shell/active_shell.dart` | go_router; 4 tabs (Today, Journey, Journal, History); `/arc/:id/...` history routes; lifecycle redirect |
| Refresh signals | `lib/app/arc_refresh.dart` | `arcRefreshProvider`, `arcsChangedProvider`, `dayChangedProvider` |
| Midnight rollover | `lib/app/day_change.dart`, `lib/app/app.dart` (`_onDayChanged`) | the ticker bumps both refresh signals after local midnight |
| Journey UI | `lib/features/journey/journey_screen.dart`, `journey_controller.dart`, `widgets/journey_path.dart`, `widgets/journey_marker.dart`, `widgets/journey_day_style.dart`, `widgets/day_detail_sheet.dart` | path view, legend, state styles, `journeyDayLabel`, read-only day detail |
| Insights UI | `lib/features/insights/insights_screen.dart`, `insights_controller.dart`, `widgets/insight_charts.dart` | "Consistency" stat with its definition footnote |
| Arc History UI | `lib/features/history/arc_history_screen.dart`, `arc_history_controller.dart`, `widgets/arc_history_tile.dart` | the Insights entry button lives here |
| Summary UI | `lib/features/summary/summary_screen.dart` | "View Journey" / Journal / Achievements for a completed Arc |
| Theme tokens | `lib/app/theme/winter_tokens.dart`, `lib/app/theme/winter_theme.dart` | `WinterColors`, `WinterSpacing`, `WinterRadii`, `WinterDurations`, `WinterMotion` |
| Reduced motion | `WinterMotion.of` (`MediaQuery.maybeDisableAnimationsOf`), `context.motion` | durations collapse to zero; ambient scene stops |
| Shared widgets | `lib/shared/widgets/winter_card.dart`, `failure_view.dart`, `loading_view.dart`, `empty_state_view.dart`, `habit_icon.dart` | card, error, loading, empty, icons |
| Labels | `lib/shared/formatting/arc_labels.dart` | `arcHeading`, `arcDateRange`, `chapterTitle`, `dayTitle` |
| Text-scale patterns | `lib/features/focus_guard/focus_guard_settings_screen.dart` (stack above 1.3×), `lib/features/journey/widgets/journey_path.dart` (extents grow with scale) | |

### C4. Native Android

| Concern | Source |
|---|---|
| Manifest | `android/app/src/main/AndroidManifest.xml`: declares `INTERNET`, `RECEIVE_BOOT_COMPLETED`, `PACKAGE_USAGE_STATS` and removes WorkManager's `FOREGROUND_SERVICE` / `ACCESS_NETWORK_STATE`. The **merged** release manifest has exactly 7 permissions ([PHASE_11F.md § K](PHASE_11F.md#k-permission-and-component-audit)). Focus Guard provider in `:focus_guard` |
| Focus Guard native code | `android/app/src/main/kotlin/com/nextrep/nextrep/focusguard/` (`FocusGuardDatabase.kt`, `FocusGuardCheckProvider.kt`, `FocusGuardWorker.kt`, …) |
| Native tests | `android/app/src/test/kotlin/com/nextrep/nextrep/focusguard/` |
| Gradle | `android/app/build.gradle.kts` (WorkManager 2.10.1) |

### C5. Tests and CI

- 84 test files under `test/`: `domain/`, `data/`, `features/`,
  `integration/`, `app/`, `shared/`, plus shared helpers in
  `test/support/` (`arcs.dart`, `builders.dart`, `fakes.dart`, `ui.dart`).
  9 on-device smokes in `integration_test/`. Backup fixtures
  `test/fixtures/phase5_backup_v1.nextrep` and
  `test/fixtures/v1_1_backup_v2.nextrep`.
- Six-layout sweep: `test/integration/phase11e_layout_test.dart`.
- CI: `.github/workflows/flutter-ci.yml` runs on every PR. Job "Format,
  analyze and test" (migrations, backups, Focus Guard, update check,
  release qualification, all tests) and job "Android builds and permission
  audit".

## D. Invariants v1.3.0 must keep (CONFIRMED in code)

| Invariant | Where it lives |
|---|---|
| A 92-day Arc; Day 1 = start (rolling) or 1 October (seasonal) | `WinterArcRules.lengthInDays`, `problemWith` |
| Late seasonal join keeps season numbering; earlier days neutral | `isBeforeJoining`, `participatingDatesThrough`, `JourneyDayState.notJoined` |
| ≤ 12 habits; goal edits apply from the next challenge day; past configuration immutable | `SetupHabitRules.maxHabits`; `HabitHistory` doc; edits built on `next ?? date` in `HabitTrackingService` |
| Completion stored against the effective target of that day; re-evaluated only while today | `DailyHabitProgress` doc; `DayRules.settle` runs only via `commitDay` on today |
| Minimum Day: today only, reversible that day, keeps habit streaks, breaks the Perfect streak, never Perfect | `DayMode`, `DaySummary.canReturnToFullTargets`, `ArcHistory.habitMarks` / `perfectMarks`, `DayRecord.isPerfect` |
| XP ledger is a function of day state; idempotent keys | `DayRules` invariants 1–3, `XpRules` keys, unique `(session_id, source_key)` |
| Streaks, levels, Perfect Days, Journey states derived, never stored | README architecture; `ArcHistory` |
| 32 achievements; 0 XP; unlocks only via reconciliation | `AchievementCatalog.all`, `AchievementService` |
| Completed Arcs are read-only | `CurrentArcService`; writes need the active Arc |
| Journal is private; insights read moods and dates only | `InsightArc` doc; `ReflectionRepository.moodsFor` |
| No network except the manual update check | `test/app/network_boundary_test.dart`, PRIVACY.md |

## E. Feature analyses

### E1. Feature A: Weekly Arc Review

| Aspect | Finding |
|---|---|
| Reuse | `ArcHistory` (`elapsedDates`, `recordOn`, `records.xpByDate`, `records.habits`), `DayRecord` / `DayCompletion`, `HabitTrackingService.history()` / `historyFor(id)`, `DayDetailSheet`, `JourneyDayState` and `journeyDayLabel` for the week strip, `arc_labels.dart`, `WinterCard`, `FailureView`, `LoadingView` |
| New | `ArcWeeks` (week arithmetic), `WeeklyReview` read model, `WeeklySummaryRules`, a controller, a screen, two routes (§ G) |
| Invariants touched | none written. It reads the stored completion flag, stored modes and the ledger |
| Data dependencies | `daily_habit_progress_entries`, `day_modes`, `xp_transactions`, `habits`, `habit_revisions`, `winter_arc_sessions` (all existing) |
| Performance | per open: the session lookup (1–2 queries) and one `loadArc` (5 SELECTs in one transaction), ≤ 8 day records. Fewer than Journey's provider, which also closes out the Arc and runs an achievement sync (a second `loadArc`). The review must not reuse that provider. No risk found |
| Testability | high: pure functions of `ArcHistory`, which tests already build from fakes (`test/support/arcs.dart`, `builders.dart`) |
| Android / iOS | pure Dart and Flutter. Identical on both. No platform channel |

### E2. Feature B: Arc Consistency Calendar

| Aspect | Finding |
|---|---|
| Reuse | `JourneyOverview.days` (all 92 `JourneyDay`s with state, record and XP), `JourneyDayStyle` (label, shape, fill, icon, dashed, opacity), `journeyDayLabel`, `DayDetailSheet` / `NotJoinedDaySheet`, Journey's legend and controllers (`journeyControllerProvider`, `arcJourneyProvider`) |
| New | the Path / Calendar switch in the Journey header, `ArcCalendar` (13 week blocks), `CalendarDayCell`, `calendarDayLabel`; `ArcWeeks` shared with 12B |
| Invariants touched | none: same states as Journey, read-only sheets |
| Data dependencies | none beyond Journey's |
| Performance | zero additional queries; 92 cells in a lazy list |
| Testability | high: build `JourneyOverview` from fake history; golden-free widget tests on semantics and the state tuples |
| Android / iOS | pure Flutter |

### E3. Feature C: Weekly Focus. See § I.

### E4. Feature D: Android widget. See § J.

## F. Decisions

### D1. Week model

| | |
|---|---|
| Decision | **Arc-relative weeks**: Days 1–7 … 78–84, then 85–92. 13 weeks. |
| Alternatives | (a) Calendar weeks, Monday–Sunday or by locale. (b) Arc weeks with a 1-day Week 14. (c) Arc weeks with Week 13 = Days 85–92 (chosen). |
| Evidence | Every screen speaks in Arc days (`dayTitle`, Journey, chapters, milestones on Days 7 / 14). No week concept exists in `lib/` (searched; only achievement titles). Seasonal 2026 starts on a Thursday, so calendar weeks would give 4 + 12×7 + 4 days, i.e. 14 weeks with two partial ones. A rolling Arc from Wed 7 Oct 2026 would give 5 + … + 3. `LocalDate` already does exact day arithmetic. |
| Trade-offs | Arc weeks don't line up with the user's Monday–Sunday. The review says "Thu 15 Oct – Wed 21 Oct" plainly. Calendar weeks would need locale week-start handling and partial weeks in every Arc. |
| Recommendation | (c). A 1-day review (b) would always be "too little data". |
| Risks | Users may expect Monday–Sunday. Mitigation: dates on every week header. Owner approval at Gate A. |
| Tests | § L, `arc_weeks_test`: boundaries for d = 1, 7, 8, 84, 85, 92; seasonal, rolling, late join; DST and zone changes. |

### D2. Metric naming: Consistency vs habit completion

| | |
|---|---|
| Decision | Headline = **Habit completion** (`C / H`). **Consistency** keeps its app-wide meaning (`F / N`), limited to the week. |
| Alternatives | (a) Use "Consistency" for `C / H`, as in the brief's example. (b) Only show `F / N`. |
| Evidence | "Consistency" = full days / days climbed in Insights (with a footnote saying so), Summary and the Arc History tile (`insights_screen.dart`, `summary_screen.dart`, `arc_history_tile.dart`; formulas in `insight_snapshot.dart`, `arc_summary.dart`). |
| Trade-offs | (a) would show two different "consistency" numbers for the same Arc. (b) is coarse and harsh: one unfinished habit makes a day not full. |
| Recommendation | Show both, named as the app already names them. Weekly consistency then adds up to the Arc's consistency. That's exact for completed Arcs; for an active Arc it holds with today's term added, because ArcSummary and Insights count today and the review doesn't (spec § 4.5). |
| Risks | None technical. Naming needs owner approval (Gate A). The weekly highlight is labelled "Most consistent this week", because Insights' "Most consistent" uses different, cross-Arc rules. |
| Tests | the reconciliation properties in spec § 4.5. |

### D3. Summaries: deterministic rules, not generated text

| | |
|---|---|
| Decision | A priority-ordered table of 9 headline rules and 2 habit lines (spec § 6), fixed English strings, no persistence. |
| Alternatives | Random variants, a language model, persisted paragraphs. |
| Evidence | The brief forbids AI, network and randomness. The app is offline-first. Insights is already "descriptive only" (`InsightRules` doc). |
| Trade-offs | Less variety. In return: testable, reproducible and private. |
| Recommendation | As specified. Nothing persisted: the text is a pure function of persisted facts, so storing it would only add a migration and a staleness risk. |
| Risks | Copy tone. Mitigation: owner copy review in 12B, plus a forbidden-word test. |
| Tests | exhaustive small-week generation for "no contradiction"; repeated runs give the same output; forbidden words absent. |

### D4. Weekly Review entry point

| | |
|---|---|
| Decision | A "Week N review" button in the Journey header (active and completed Arcs), plus links from the calendar week headings. Routes `/journey/review?week=N` (root navigator) and `/arc/:id/review?week=N`. |
| Alternatives | Today card; Insights; a fifth tab; Arc History. |
| Evidence | Journey is the per-Arc progress screen; Insights is cross-Arc and reached from History (`arc_history_screen.dart`). Root-navigator sub-routes already exist (`/today/habits` with `parentNavigatorKey: rootKey`). `AppRoutes.redirect` already guards `/journey` and `/arc/:id`. |
| Trade-offs | One tap further than a Today card. Today stays focused on action. |
| Recommendation | As specified. A Today card can be considered after v1.3 usage. |
| Risks | Discoverability. Mitigation: the calendar's week headings are a second, visible path. |
| Tests | route tests for both paths, malformed `week`, the redirect with no active Arc, Back returning to Journey. |

### D5. Calendar placement and structure

| | |
|---|---|
| Decision | A Path / Calendar switch inside Journey. 13 Arc-week blocks. |
| Alternatives | A separate screen or tab; a month grid; a 92-cell undifferentiated grid. |
| Evidence | `JourneyOverview.days` already holds everything (`journey_overview.dart`). Month grids need locale week starts and leading blanks, and rolling Arcs span four months. |
| Trade-offs | A month view would show familiar dates. Week blocks show dates in their headings instead. |
| Recommendation | As specified. |
| Risks | A crowded Journey header. Mitigation: the header already scrolls within half the height (`journey_screen.dart` `ConstrainedBox`). |
| Tests | spec § 11 K1–K6. |

### D6. Calendar states: reuse `JourneyDayState`

| | |
|---|---|
| Decision | No new classifier. The calendar renders `JourneyDay.state`. |
| Alternatives | A calendar-specific state set (for example "all full targets achieved" on Minimum Days). |
| Evidence | `JourneyDayState` is already single-valued with a precedence (`journey_day.dart` table, `JourneyRules.stateOf`, `ArcHistory._journeyDay`). Its styles already differ by shape, fill, icon and label (`journey_day_style.dart`). |
| Trade-offs | The calendar can't show a state Journey doesn't have. That's on purpose: the two views must never disagree. |
| Recommendation | As specified (spec § 7.2). |
| Risks | Wording of "Missed" (UNRESOLVED, copy). |
| Tests | Journey and the calendar give the same state for every day of generated Arcs; a precedence table test. |

### D7. No persistence or caching

| | |
|---|---|
| Decision | Neither feature stores anything. No read-model cache. |
| Evidence | `loadArc` is already one batched snapshot. Journey derives 92 days the same way today without a performance finding (Phase 11E § M: no performance defect). |
| Recommendation | Revisit only if 12E profiling shows a problem. |
| Tests | a counting fake `ProgressRepository`: one `loadArc` per review open, none extra for the calendar. Every table byte-identical after opening reviews, and after switching a loaded Journey to Calendar. Journey's own entry-point writes (close-out, achievement sync) already exist and aren't part of this check. |

### D8. Placement of new code

| | |
|---|---|
| Decision | `ArcWeeks` in `lib/domain/journey/arc_weeks.dart` (next to chapters and milestones, which are the existing day-position structures). Review domain in a new `lib/domain/review/`. Review UI in a new `lib/features/review/`. Calendar UI in `lib/features/journey/widgets/`. |
| Alternatives | An "ArcMomentumRepository" or a `momentum/` package. |
| Evidence | The convention is `domain/<area>/` with `*_rules.dart` (pure) and read models built `fromHistory` (`JourneyOverview.fromHistory`, `ArcSummary.fromHistory`, `DaySummary.fromHistory`). No repository is needed: no new data. |
| Recommendation | No new repository. A thin controller over `HabitTrackingService.history()` / `historyFor(id)`. |

## G. Shared Arc Momentum architecture (PROPOSED)

| Component | Responsibility | Inputs | Outputs | Dependencies | Errors | Tests | Persistence |
|---|---|---|---|---|---|---|---|
| `ArcWeeks` (`lib/domain/journey/arc_weeks.dart`) | week arithmetic, day classes, week status, reviewable range | `WinterArcSession`, `LocalDate today` | `ArcWeek {number, firstDay, lastDay, dates, status}` | `winter_arc_session.dart` | `ArgumentError` for w ∉ 1..13 (programming error). Routes clamp before calling | pure unit | none |
| `WeeklyReview` + `WeeklyReview.fromHistory(history, week:)` (`lib/domain/review/weekly_review.dart`) | the spec § 4 metrics, per-habit tallies, today block, highlights | `ArcHistory`, week number | immutable read model | `ArcWeeks`, `ArcHistory` | none beyond `ArgumentError` | pure unit + property | none |
| `WeeklySummaryRules.summarize(review)` (`lib/domain/review/weekly_summary_rules.dart`) | the spec § 6 rules | `WeeklyReview` | `WeeklySummary` (kind, tense, flags, highlights) | none | none (total function) | exhaustive unit | none |
| Summary copy (`lib/features/review/weekly_summary_text.dart`) | maps `WeeklySummary` to the exact strings | `WeeklySummary` | `String` | none | none | unit (exact strings, forbidden words) | none |
| `weeklyReviewProvider` (`lib/features/review/weekly_review_controller.dart`) | loads history for the active or a given Arc; clamps `week` | `({int? sessionId, int? week})` | `AsyncValue<WeeklyReview>` | `habitTrackingServiceProvider`, `arcRefreshProvider`, `dayChangedProvider` | `PersistenceFailure` → `FailureView` | provider + widget | none |
| `WeeklyReviewScreen` (`lib/features/review/weekly_review_screen.dart`) | spec § 5 | provider | UI | `DayDetailSheet`, `WinterCard`, labels | `FailureView` | widget, layout sweep | none |
| `ArcCalendar`, `CalendarDayCell`, `calendarDayLabel` (`lib/features/journey/widgets/`) | spec § 7 | `JourneyOverview` | UI | `ArcWeeks`, `JourneyDayStyle`, `DayDetailSheet` | inherits Journey's | widget, semantics | none |

```
           Drift (schema v6, unchanged)
                     │  ProgressRepository.loadArc (1 tx, 5 SELECTs)
                     ▼
     ArcRecords ──► ArcHistory(session, records, Clock.today())
                     │                         │
       JourneyOverview.fromHistory      WeeklyReview.fromHistory(week)
         │              │                         │
   Journey Path    ArcCalendar ──week link──► WeeklySummaryRules
   (existing)      (12C)                          │
         └──────┬──────┘                 WeeklyReviewScreen (12B)
                ▼                                 │
         DayDetailSheet (existing, read-only) ◄───┘
```

A Mermaid version is in [ARC_MOMENTUM_SPEC.md § 9](ARC_MOMENTUM_SPEC.md#9-data-flow).
**No new repository, no new table, no service with write access.**

## H. Data-model findings

### H1. Do the guaranteed features need database changes? **NO** (CONFIRMED)

Every input is already persisted and already read by `loadArc`:

| Needed | Stored as |
|---|---|
| Which habits applied on a date, and their targets | `habits` (baseline) + `habit_revisions` (dated) → `HabitHistory.planFor` |
| Day mode | `day_modes` (absent = normal) |
| Per-habit completion | `daily_habit_progress_entries.completed` |
| Perfect / Minimum completion | derived from the above (`DayRecord`) |
| XP per date | `xp_transactions.date`, summed by `loadArc` |
| Week boundaries | derived from `winter_arc_sessions.start_date`, `participation_start_date` |
| Calendar states | derived (`JourneyDayState`) |
| Summaries | derived (never stored) |

**Backup format: NO change.** Nothing new to export. Restore gives back the
inputs, and reviews and calendars are rebuilt from them, so they're
identical after a restore by construction. Backups from v1.0.0 (format 1),
v1.1.0 (format 2) and v1.2.0 (format 3) restore exactly as today. A 12B
repository test restores the two committed fixtures and computes reviews
from them.

The one subtlety (CONFIRMED): restored ledgers are validated for key
format and amount range (1..1000), not for agreement with completion. So
XP is always **read from the ledger**, never derived (spec § 4.5).

### H2. Schema and backup rules carried into v1.3

- `schemaVersion` stays 6, `BackupFormat.formatVersion` stays 3, and
  `readableVersions` stays {1, 2, 3}.
- No migration test changes. CI's migration (v1 → v6) and backup (1 / 2 /
  3) suites must stay green unchanged through 12F.
- A v1.3.0 backup is the same format 3, readable by v1.2.0 as well.

## I. Feature C: Weekly Focus feasibility → **DEFER**

**Concept:** the user picks one existing habit as next week's focus,
shown as a label on Today and in the review. No XP, streak, goal, Perfect
Day or Minimum Day effect, and no reminder.

| Question | Finding |
|---|---|
| Owned by | An Arc **and** an Arc week (`session_id`, `week_number`). A focus can't outlive its Arc. |
| Changes | Replaceable or clearable while its week is current or upcoming; frozen once the week is final (as with Minimum Day, the past doesn't change). |
| Survives restarts | Only if persisted. It can't be derived: it's a user choice. |
| Arc ends | Frozen with the Arc (read-only history). The next Arc starts without a focus. |
| Backup restore | Must be in the backup, or a restore silently drops a user choice. |
| Habit disabled later | The focus stays as history. From the next day the label shows "(paused)". It never re-enables or changes the habit. |
| Goal changes | No interaction: the focus names a habit, not a target. |
| Summaries | Would need focus-aware rules ("You gave Reading your focus: 5 of 7 days"), which add priority cases to spec § 6. |

**Persistence it would need (outline only, not built):**

- Schema v7, additive: `weekly_focus(session_id INTEGER REFERENCES
  winter_arc_sessions ON DELETE CASCADE, week_number INTEGER CHECK 1..13,
  habit_id TEXT, chosen_at DATETIME, PRIMARY KEY (session_id,
  week_number), FOREIGN KEY (session_id, habit_id) REFERENCES habits ON
  DELETE CASCADE)`. A `migration_v7_test`, a new `drift_schemas` snapshot,
  and CI's migration step extended to v7.
- Backup format 4: an optional `focus` list per Arc. The validator checks
  the week range, an existing habit, a week not before the join week and
  not after the export date's week. Write 4, read 1–4.
- Compatibility cost: **v1.2.0 rejects format-4 files** ("made by a newer
  version", per the existing `readableVersions` rule). Moving data back to
  v1.2 would then need an older backup. This is the same trade-off v1.2 made
  for format 3, but it's a new cost paid for a label.

**Verdict: DEFER** (not NO-GO).

1. It is the **only** v1.3 candidate that would need a migration and a new
   backup format. Both guaranteed features need neither. Adding it would
   turn a zero-migration release into a migration release, with all the
   upgrade-rehearsal weight that carries in 12F.
2. Most of its value is already delivered without state. The review's
   "Room to grow" habit, worded as "could use a little more attention next
   week", is a derived, honest focus suggestion.
3. Its usefulness is unproven. Whether users want to *choose* a focus is
   better judged after v1.3's derived suggestion has been used.
4. Re-evaluate for v1.4. The owner can override this verdict at Gate A
   (see [V1_3_ROADMAP.md](V1_3_ROADMAP.md#approval-gates)).

## J. Feature D: Android home-screen widget feasibility → **DEFER**

**Concept:** a small widget with the current Arc day and today's
completion; tap to open NextRep.

| Question | Finding |
|---|---|
| Integration options | (1) A hand-written `AppWidgetProvider` + `RemoteViews` in Kotlin, fed by Dart over a method channel (no new dependency). (2) The `home_widget` plugin (a new dependency, so not allowed in this phase, and it needs review). Flutter can't render a home-screen widget itself. |
| Existing native architecture | Kotlin only for Focus Guard (`focusguard/`), whose `:focus_guard` process is "the only one that opens NextRep's database outside Flutter" (`FocusGuardDatabase.kt`). Drift's bundled SQLite and Android's SQLite must never share a process. |
| Where today's completion comes from | It can't be computed natively without re-implementing `HabitHistory.planFor` + `DayRules` (revisions, enabled days, Minimum Day targets) in Kotlin, which would be a **second progress engine**. So natively computed completion is rejected. |
| Safe read-only design | Dart writes a tiny snapshot (`date`, Arc day, completed, total) to app-private storage after each `commitDay` and each day change, then asks the widget to refresh. The widget only reads the snapshot. **No SQLite access from the widget, no new writer to `nextrep.sqlite`.** |
| Lifecycle, refresh, battery | Launcher-driven `onUpdate` (`updatePeriodMillis` ≥ 30 min). Updates come from app writes. No alarms, no WorkManager job, no wake-ups of its own. Negligible battery cost. |
| Stale data | After midnight the snapshot is from yesterday. The widget must check `snapshot.date == today` and otherwise show "Day N · Open NextRep" (the day number is pure date arithmetic from the snapshot's start date). It can't show today's completion until the app runs. |
| Force-stop | Android stops broadcasts to a force-stopped app, so the widget freezes until NextRep opens. The date check keeps it truthful. |
| Reboot | The launcher re-inflates the widget from the last `RemoteViews`. The date check applies. |
| Restore / app data cleared | The snapshot is removed with app data. The widget shows "Open NextRep". A backup restore must rewrite the snapshot. |
| Permissions | None new. `APPWIDGET_UPDATE` is a protected system broadcast. But the provider is an **exported receiver**, which the release component audit in CI and `tool/release/` would have to allow explicitly. |
| Privacy | Home screen: counts only, no habit names, no journal. Lock screen: phone lock-screen widgets depend on the Android version and OEM (UNRESOLVED; needs physical qualification). The widget must not show progress there by default. |
| Launchers, resizing | Pixel Launcher vs OxygenOS launcher differ in cell sizes and resize behaviour. A 2×1 minimum layout. Needs device testing on both. |
| Android versions | `AppWidgetProvider` is available on minSdk 24. Android 12+ adds rounded-corner and sizing APIs. |
| iOS | WidgetKit needs a Swift extension and an App Group, so it's a separate design. There is no iOS release, so it's out of scope. |

**Verdict: DEFER** (not NO-GO). A read-only, permission-free design exists.
But it brings native Kotlin, an exported component, release-audit changes,
a Dart→native snapshot contract with its own staleness rules, and a
launcher × Android-version physical matrix. That's the kind of work that
needed its own feasibility probe in v1.2 (Phase 11A). None of it serves the
guaranteed features, and it could delay them. Recommended as a separate
v1.4 feasibility phase with a debug-only probe on the emulator and the
OnePlus, after owner authorization.

## K. Risks and mitigations

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | Users expect Monday–Sunday weeks | medium / low | dates on every header; Gate A approval of D1 |
| R2 | "Consistency" and "habit completion" confused | medium / medium | D2 naming; reconciliation tests; the Insights footnote's definition reused |
| R3 | Summary copy feels judgemental | low / high | forbidden-word test; owner copy review in 12B; no highlights on small samples or quiet weeks |
| R4 | Today's partial day looks like a miss | low / high | today kept out of the totals, in its own "so far" block; tests at 00:00:01 and 23:59:59 |
| R5 | The calendar disagrees with Journey | low / high | one computation (`JourneyDay.state`); an equality test over generated Arcs |
| R6 | Minimum Day shown as Perfect | low / high | different shape, icon and label; precedence test |
| R7 | XP mismatch on restored data | low / medium | XP read from the ledger only (H1) |
| R8 | Hidden extra queries (N+1) | low / medium | a counting fake repository in 12B / 12C tests |
| R9 | Layout overflow at 2× text | medium / medium | 4-per-line calendar rule; layout sweep; an emulator check at 2× / 360 dp, because the test font's glyphs differ from the device's ([PHASE_11E.md § N](PHASE_11E.md#n-accessibility-and-ui-review)) |
| R10 | Scope creep from the conditional features | medium / high | both DEFER; Gate A records it; 12D gets a bounded hardening scope instead |
| R11 | Midnight with a screen open | low / medium | existing `_onDayChanged` signals; a test with a fake clock across midnight |
| R12 | Accidental write while viewing | low / high | a test: every table byte-identical before and after opening reviews, and after switching a loaded Journey to Calendar. The review provider never reuses `journeyControllerProvider`, which can write (close-out, achievement sync) |
| R13 | Calendar cells below 48 dp, or low-contrast glyphs | medium / medium | 8 dp grid gutter so 7 cells fit at ≥ 352 dp, 4 per line otherwise (spec § 7.4); `textSecondary` outlines for future / neutral cells, with a token contrast test (A12) |

## L. Test plan for Phases 12B–12F

Layers: **U** pure Dart unit, **R** repository / database (in-memory Drift
or the restored fixtures), **W** widget, **I** integration (`test/integration/`,
CI), **J** Android JVM, **E** emulator, **P** physical device,
**S** iOS simulator.

### L1. Weekly Review (12B)

| Case | Layer |
|---|---|
| `ArcWeeks`: `weekOf` for d = 1, 7, 8, 14, 84, 85, 91, 92; `dates(w)` for rolling (Wed start) and seasonal 2026 (Thu); Week 13 has 8 days | U |
| Day classes and week status: neutral / upcoming / open / settled precedence; `beforeJoining`, `complete`, `inProgress`, `upcoming` | U |
| Reviewable range: rolling from Week 1; late join Day 18 starts at Week 3; completed Arc 1..13 / join..13 | U |
| Arc start (Day 1 = today: START), Arc end (Day 92 open; then complete after close-out) | U |
| Current partial week: totals exclude today; the today block matches `r(T)` | U |
| Completed week totals (spec example 1, exact numbers) | U |
| Future days never in `H` / `N`; neutral days never in `H` / `N` (example 3) | U |
| Minimum Day: counted at minimum targets; `M` vs `Mc`; returned-to-full day counts as normal | U |
| Perfect Day count equals `isPerfect` days only | U |
| Partial habit progress (count 5/8, duration 20/30) not completed | U |
| Every `HabitType`, including Sleep Before (a logged time later than the target is not completed) | U |
| Goal revision mid-week (example 4); disabled habit mid-week | U |
| XP = ledger sum; reconciliation identities § 4.5 over generated Arcs | U (property) |
| Highlights: thresholds, tie-breaks, single habit, all tied, `N < 3`, `a < 3`, `C = 0` | U |
| Summary rules: each of the 9 kinds; the first match wins; tense and final-week variants; no contradiction (exhaustive over generated 3-habit weeks); determinism (100 runs identical); forbidden words | U |
| Midnight rollover with a fake clock: the open week gains a settled day; Week 13 closes out with a redirect | W |
| Time-zone change (today moves back a day): recomputed, no error | U + W |
| Restored backups: fixtures `phase5_backup_v1.nextrep`, `v1_1_backup_v2.nextrep` and a format-3 export restore, then reviews compute and match the expectations | R |
| Historic completed Arc: same review for any later `today` | U |
| Opening reviews writes nothing (all tables identical) | R |
| One `loadArc` per open (counting fake) | W |
| Routes: `/journey/review?week=`, `/arc/:id/review?week=`; malformed week; no active Arc; Back to Journey | W (`test/app/app_routes_test.dart` extension) |
| Screen states § 5.3 (loading, error with retry, empty, first week, completed Arc) | W |
| Semantics labels, tap targets, contrast guidelines | W |

### L2. Calendar (12C)

| Case | Layer |
|---|---|
| All 8 states rendered with their style tuple; precedence table | U + W |
| Calendar state == Journey state for every day (generated Arcs, many `today`s) | U |
| 92-day boundaries: 13 blocks, Week 13 with Day 92 wrapped | W |
| Seasonal dates (Thu–Wed 2026), rolling dates crossing the year in headings | W |
| Neutral weeks and days of a late join; future days not tappable | W |
| Current day outline and "This week"; opens scrolled to the current week | W |
| Goal changes don't alter past cells | U |
| Historical immutability: completed Arc output identical for later `today` | U |
| Maximum 12 habits × 92 days with heavy revisions: builds without extra queries; timing recorded, not gated | W + E (profile) |
| Multiple completed Arcs: each calendar shows its own Arc (`/arc/:id/journey`) | W |
| Read-only navigation: taps open `DayDetailSheet` / `NotJoinedDaySheet`; no write path reachable | W |
| Week heading opens the review for that week | W |
| Accessibility: labels with date and state, focus order, 4-per-line at > 1.3× or < 352 dp, 48 dp targets, guidelines | W |
| Non-text contrast of every state's outline ≥ 3:1 against `surface` (A12) | U |

### L3. Weekly Focus: only if approved later (not planned for v1.3)

Selection, replacement, clearing, freeze at week end, Arc completion,
restore (formats 1–4), a habit disabled after selection, historical
boundaries, XP / streak / Perfect / Minimum unchanged (ledger byte-identical),
migration v6 → v7 (R), downgrade rejection of format 4 by the v1.2 rules (R).

### L4. Widget: only if approved later (not planned for v1.3)

Install / place / resize on two launchers (E, P); snapshot refresh after a
habit action (W + J); midnight staleness (date check) (J); reboot (E, P);
force-stop (E, P); lock-screen exposure (P); app data cleared / uninstall
(E); background restrictions (P); restore rewrites the snapshot (W);
component audit allows exactly the provider (CI).

### L5. Release regression (12E, 12F)

The full existing suite must stay green and unmodified in intent: Arc
lifecycle, habit progress, XP, streaks, Minimum Day, Perfect Days,
achievements (32, backfill), Journal, reminders, Hydration Coach, Focus
Guard (including 67 JVM tests), backup and restore (formats 1 / 2 / 3),
migrations v1 → v6, the manual update check and the network boundary,
share cards, layout sweep, iOS simulator smokes. New 12E suites:
`test/integration/phase12e_*` (combined flow with the review and calendar,
the layout sweep extended to both new screens, restore then review).

### L6. Device qualification

- **Emulator (12E):** a disposable or `.qualification` package; review and
  calendar at 1× and 2× / 360 dp; TalkBack reading order; reduced motion;
  midnight with a screen open; a profile-build timing of the review and
  calendar.
- **Emulator (12F):** signed v1.2.0 → v1.3.0 `adb install -r` rehearsal
  on a disposable AVD with synthetic data; every table identical before and
  after (no migration expected).
- **Physical OnePlus (12F only, after explicit owner authorization):**
  signed in-place upgrade, data preservation, smoke of the review and
  calendar. **Not required and not done in 12A.**

## M. Open questions

| # | Question | Type | When |
|---|---|---|---|
| Q1 | Approve the Arc-week model (D1) | owner decision | Gate A |
| Q2 | Approve the naming "Habit completion" + "Consistency" (D2) | owner decision | Gate A |
| Q3 | Confirm Weekly Focus DEFER and widget DEFER | owner decision | Gate A |
| Q4 | Rename the `missed` label to "No progress" in Journey, the calendar and the week strip. Recommended: today a past Minimum Day with no progress reads "Missed" | owner copy decision | 12C |
| Q5 | Summary copy sign-off (spec § 6 tables) | owner copy review | 12B |
| Q6 | TalkBack reading order and 2× layout on a real device | later qualification (emulator 12E, OnePlus 12F) | 12E / 12F |
| Q7 | Phone lock-screen widget exposure on Android 16 / OxygenOS | later qualification, only if the widget is revived | v1.4 |

None of these blocks the plan.

## N. Phase 12A qualification results

| Check | Result |
|---|---|
| Baseline: `origin/main` = `28db2af`, tag `v1.2.0` → `8ab0c43`, release v1.2.0 public with both assets | PASS |
| Clean worktree from the verified commit; primary checkout and other worktrees untouched | PASS |
| Every source path cited in the three documents exists (script over all `lib/`, `android/`, `test/`, `tool/`, `.github/` paths) | PASS |
| Relative Markdown links and anchors between the new documents resolve | PASS |
| Independent read-only review of every code claim and of the worked-example arithmetic against the source | 9 factual and 11 logic findings, **all corrected** before commit: the Journey marker's today border is 3 dp and its glow is static; Journey dims the whole marker; the review's query count vs Journey's provider; today in the consistency reconciliation; scoping of the no-write check; restored completion flags; the manifest vs merged permission count; the layout list; 48 dp calendar cells; the Room-to-grow tie rule; Minimum Day "Missed" wording; final-week copy; `H = 0` and floored comparisons; the over-but-not-closed and before-join edges; non-text contrast; emulator work placed in 12E. All arithmetic, weekdays and contrast values were confirmed |
| `git diff --stat` against `28db2af`: only `docs/PHASE_12A.md`, `docs/V1_3_ROADMAP.md`, `docs/ARC_MOMENTUM_SPEC.md`, `PROJECT_STATE.md` | PASS |
| `git diff --check` (whitespace) | PASS |
| No file under `lib/`, `android/`, `ios/`, `test/`, `integration_test/`, no `pubspec.*`, `.github/`, `tool/` changed; version `1.2.0+3` | PASS |
| No sensitive data (no keystore, `key.properties`, passwords, tokens, personal backups, device identifiers beyond the published model) | PASS |
| Physical phone, emulator, APK | not used / not built |
| GitHub Actions on the PR's final head | see the PR (recorded in the final report; CI runs normally for docs-only PRs) |

Not run, on purpose: `flutter test`, Android and iOS builds. They aren't
required for a documentation-only change, and CI runs them on the PR
anyway.

## O. Next phase

Phase 12B (Weekly Arc Review) starts only after the owner reviews this PR
and passes Gate A ([V1_3_ROADMAP.md](V1_3_ROADMAP.md#approval-gates)).
