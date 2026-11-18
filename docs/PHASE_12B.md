# Phase 12B: Weekly Arc Review

## Objective and boundary

The first v1.3.0 user-facing feature: a **read-only** review of each
week of a Winter Arc, built exactly on the approved
[ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md) (§§ 3–6, 8–11 and the § 12
lifecycle addendum, which wins where they differ) and the merged
Phase 12E1 day ↔ date mapping ([PHASE_12E1.md](PHASE_12E1.md)).

Opening or browsing a review stores, awards and sends nothing. No schema,
migration, backup, Focus Guard, permission, dependency, version, XP,
achievement, streak, Perfect Day or Minimum Day change. No Freeze, Resume,
Restart, deletion, sound or Calendar (Phase 12C). No new tab. Version
`1.2.0+3`; no release; no physical phone; no production signing.

## Verified baseline

| | |
|---|---|
| `origin/main` | `7e5ece40ae2c2a3ee24bebae38d24a9d440be9a0`, "Phase 12E1: v1.3 lifecycle foundation (#24)", the expected baseline; nothing landed after it |
| PR #24 | merged 14 Nov 2026 |
| Schema | `AppDatabase.schemaVersion` 7 |
| Backup | `BackupDocument.formatVersion` 4 (reads 1–4) |
| Version | `1.2.0+3` |
| Focus Guard | native gate `FocusGuardStore.SCHEMA_VERSION` 7 |
| Existing 12B work | none: no branch, PR or worktree |
| Worktree | `~/labs/NextRep-12B`, new branch `phase/12b-v1.3-weekly-review` from `7e5ece4`; the primary checkout and the other worktrees were not touched |

## What was built

| File | Role |
|---|---|
| `lib/domain/journey/arc_weeks.dart` | `ArcWeeks`: the 13 Arc weeks, day classes, week statuses, reviewable / default / previous / next / nearest week. Pure |
| `lib/domain/progress/arc_history.dart` | `ArcHistory.journeyDay(n)`: one day exactly as `journey()` lists it (a pure refactor; `journey()` now calls it), so the strip reuses the Journey's state engine without building 92 days |
| `lib/domain/review/weekly_review.dart` | `WeeklyReview.fromHistory(history, week)`: metrics, per-habit tallies, Today so far, highlights. Immutable, pure |
| `lib/domain/review/weekly_summary_rules.dart` | `WeeklySummaryRules.summarize`: the nine kinds, tense, flags. Pure |
| `lib/features/review/weekly_summary_text.dart` | The approved sentences, chosen by the summary model only |
| `lib/features/review/review_labels.dart` | Week status and date-range wording; header and day-cell semantics labels |
| `lib/features/review/weekly_review_controller.dart` | `weeklyReviewSourceProvider`: one read-only snapshot per load |
| `lib/features/review/weekly_review_screen.dart` | The screen (spec § 5) |
| `lib/app/router/app_router.dart` | `/journey/review?week=N` (root navigator, child of Journey) and `/arc/:sessionId/review?week=N`; `reviewWeekOf` |
| `lib/features/journey/journey_screen.dart` | The header's "Week N review" button |

## Arc weeks (§§ 3.2, 12.2)

Exactly 13 weeks: `firstDay(w) = 7(w − 1) + 1`, `lastDay(w) = 7w`,
`lastDay(13) = 92`, `weekOf(d) = min(13, (d − 1) ~/ 7 + 1)`. Week 13 has
8 days and holds Day 92; there is no Week 14 and no calendar or locale
week. Every date is `WinterArcSession.dateOfDay(d)`, never
`startDate + (d − 1)`; a day after the start of an open pause has no date
(never an estimate). A paused date belongs to no week.

**Day classes** (§ 12.3, in order): `neutral` (before a late join),
`notReached` (an ended Arc's day after `closedOn`), `upcoming` (after
today, or undated), `open` (today, participating, Arc not ended:
`isOpenOn`), `settled` (participating and before today; for an ended Arc
also on today).

**Week statuses** (in order): `beforeJoining`, `notReached`, `complete`
(last date known and before today; or ended with a settled day),
`inProgress` (not ended, today participating and in the week), `paused`
(not ended, today paused, the week holds the next challenge day),
`upcoming`. Reviewable: complete, in progress, paused.

**Which week opens:** in progress, else paused, else the latest
reviewable (Week 13 of a completed Arc, the `closedOn` week of an ended
Arc). A requested week that is reviewable opens; one that can't be opened
opens the nearest reviewable week; a missing, non-numeric or out-of-range
week opens the default. With no reviewable week (before the participation
start) the route shows "Your first week review appears once your Arc has
started." and the Journey hides the button.

## Metrics (§ 4.2) and highlights (§ 4.4)

Over the week's settled dates only: `N` days, `H` opportunities, `C`
completed habit-days (stored flags, never re-scored), habit completion
`(100·C) ~/ H` (none when `H = 0`), full days `F`, consistency
`(100·F) ~/ N` (none when `N = 0`), Perfect `P`, Minimum chosen `M` and
completed `Mc`, XP `X` from the ledger only. Per habit `a(i)` and `c(i)`.
Today so far (in-progress week only, never an ended Arc): today's
completed / enabled habits, ledger XP and mode, never in a total.

Highlights need `N ≥ 3` and `a(i) ≥ 3`. Ranking compares exact ratios
(`c(i)·a(j) > c(j)·a(i)`), then more completed days, then display order.
**Most consistent this week**: the top-ranked habit with `2c ≥ a`.
**Room to grow**: `2c < a`, `C ≥ 1`, and another eligible habit with a
strictly higher ratio; lowest ratio, then more applicable days, then
display order. The two are never the same habit (property-tested).

## Summary rules (§ 6) and the copy for Gate B

Nine kinds, first match wins: START (`N = 0`), LOW_DATA (`N ≤ 2`),
ALL_FULL (`F = N`), HIGH (floored completion ≥ 80), RECOVERY (a day under
half followed later by a full day), MINIMUM (`Mc ≥ 1`), STEADY (floored ≥
50), SOME (`C ≥ 1`), QUIET. Tense: in progress for in-progress and paused
weeks, complete otherwise. Final-week wording for a complete Week 13 and
for an ended Arc's `closedOn` week. Pure: no randomness, clock, locale,
network, model or storage.

**Every sentence the summary can show** (habit titles are the user's):

| Kind | In progress | Complete | Final week (complete) |
|---|---|---|---|
| START | first week: "Your Arc is just getting started. More days will reveal your rhythm." · otherwise: "A new week begins today. One habit at a time." · **paused, nothing settled: "This week begins when you resume."** | (not possible) | (not possible) |
| LOW_DATA | "Just a few days in. Your rhythm will show as the week goes on." | "A short first week. More days will reveal your rhythm." | "A short final week. Every day you showed up counts." |
| ALL_FULL | "Every day so far this week has been a full day." | "Every day this week was a full day. That's real momentum." · with a completed Minimum Day: "Every day this week was a full day, Minimum Days included. That's real momentum." | as complete |
| HIGH | "You've kept showing up so far this week. Keep that momentum going." | "You kept showing up this week. Keep that momentum going." | "You kept showing up all the way to the summit." · **ended Arc: the complete-week sentence** |
| RECOVERY | "You found your way back this week. Every return matters." | same | same |
| MINIMUM | "On harder days you chose a Minimum Day and still showed up." | same | same |
| STEADY | **"You completed at least half of your habits so far this week. Small steps add up."** | "You completed at least half of your habits this week. Small steps add up." | as complete |
| SOME | "This week has had its challenges, and you're still making progress." | "This week had its challenges, and you still made progress. Next week is a fresh start." | "This week had its challenges, and you still made progress." |
| QUIET | "A quiet start to the week. One habit is a good place to begin." | "This week was quiet. Whenever you're ready, one habit is a good place to start." | "The final week was quiet. Reaching the end of an Arc still matters." |
| Most consistent | "{Habit} has been steady so far: {c} of {a} days." | "{Habit} was a steady part of your week: {c} of {a} days." | as complete |
| Room to grow | "{Habit} could use a little attention in the days ahead." | "{Habit} could use a little more attention next week." | "{Habit} had the most room to grow this week." |

**Three decisions for the owner (Gate B), in bold above:**

1. **Ended Arc, HIGH, final week.** § 12.3 gives an ended Arc's last week
   the final-week wording, but "…all the way to the summit." would claim a
   summit the Arc never reached (an ended Arc never earns Summit). It
   keeps the approved complete-week HIGH sentence instead. Every other
   final-week sentence applies to ended Arcs as specified. A test asserts
   no ended-Arc summary mentions the summit.
2. **Paused week with nothing settled.** START's "A new week begins
   today." is false while paused, so the summary shows the approved
   paused line "This week begins when you resume." (§ 12.3) instead, and
   the stats and "Stats appear…" line are hidden.
3. **STEADY in progress.** The spec writes it as "…so far this week. Small
   steps add up."; the full sentence used is the complete-week sentence
   with "this week" replaced by "so far this week".

### Gate B outcome

**APPROVED by the owner on 18 November 2026.** The owner formally approved
the Weekly Review summary copy in the table above, as implemented at
`79e05ee` (PR #25), including all three 12B decisions: (1) an ended Arc's
last week keeps the complete-week HIGH sentence instead of the "summit"
sentence; (2) a paused week with nothing settled shows "This week begins
when you resume."; (3) the full STEADY in-progress sentence. No wording
changed with the approval. The PR stays unmerged pending a final
independent verification; the owner merges it.

**Other review wording added in 12B** (from the § 5.2 wireframe or new,
for the same sign-off): "Week N review" (Journey button, title); "Week N of
13 · Days a–b"; "Thu 15 Oct – Wed 21 Oct · In progress | Complete |
Paused"; "· includes a 9-day pause"; "Sun 8 Mar – paused"; "Dates are set
when you resume" (no date known); "Paused since Wed 11 Mar"; stat labels
HABIT COMPLETION ("14 of 15 · 93%", "3 days counted"), CONSISTENCY ("66% ·
2 of 3 days full"), XP EARNED ("+270 XP"), PERFECT DAYS, MINIMUM DAYS
("1 completed · 2 chosen"); "TODAY SO FAR (DAY 18)", "2 of 5 habits · 30
XP · Minimum Day", "Today counts once it ends."; "MOST CONSISTENT THIS
WEEK", "ROOM TO GROW", "HABITS THIS WEEK", "6 of 7 days"; "Stats appear
after your first full day this week."; footnotes "Counts finished days;
today is added when it ends. Viewing a review never changes XP or
progress." (in progress) and "Counts finished days. Viewing a review never
changes XP or progress." (otherwise); day-cell labels such as "Day 18,
Sunday 18 October. Today. 40 percent complete." and "Day 26. Upcoming. Its
date is set when you resume."

The week strip keeps the shared Journey label "Missed" (renaming it is
Phase 12C / Gate C). The forbidden-word test covers every authored
summary sentence for every kind, tense and flag combination (576
renderings): no "failed", "missed", "lazy", "weak", "bad", "only", "poor",
"worst", "shame", "behind" or "should have".

## Read-only data flow

`weeklyReviewSourceProvider(sessionId?)` → `HabitTrackingService.history()`
(home Arc: two session lookups) or `historyFor(id)` (one lookup) → one
`ProgressRepository.loadArc` (one transaction) → `ArcHistory(session,
records, Clock.today())` → `ArcWeeks` once → `WeeklyReview.fromHistory`
per shown week, in memory. Changing weeks reads nothing. It never calls
`ArcLifecycleService.reconcile`, `AchievementService` (sync, reconcile,
backfill), `commitDay`, a reminder scheduler or `journeyControllerProvider`
(a source scan in the tests forbids each). It re-reads on
`arcRefreshProvider`, `dayChangedProvider` and app resume; a result for
another Arc is never shown; the previous review stays on screen while a
refresh loads; the shown week is kept across refreshes (midnight).

## Freeze, ended Arcs and clock rollback

- **Paused week:** reviewable with zero or more settled days; totals so
  far; "Paused since <date>"; no Today so far; undated days upcoming. On
  resume it is in progress again from the right day; a complete week is
  identical before the pause, during it and after the resume; Week 13
  keeps 8 days through a pause.
- **Ended Arc:** reviews stop at the `closedOn` week (later weeks not
  reached); that week is complete and final; no Today so far; `closedOn`
  counted once when `T ≥ closedOn`, not at all when the clock is behind
  it; nothing is reconciled or written.
- **Clock rollback** (real Drift, the app's own write path, injected
  clock; PHASE_12A § L1 steps 1–15 at D − 1, D and D + 1): normal active
  Arc; Day 7 / Day 8 boundary; before the participation start (Rolling
  started on D and Seasonal joined on D); late Seasonal join; completed
  Arc rolled back into (stays completed); ended Arc (`closedOn = D`);
  before, inside and after a pause, before and after Resume. At every
  step the XP ledger rows are byte-identical (id, source key, reason,
  amount, habit, date, created at), no source key is duplicated, total XP
  is unchanged and **every table** is identical before and after the read.

## XP and day reconciliation

For every review the four XP groups of § 12.5.1 (settled, today, future,
other) sum to `totalXp`, `other = 0`, settled = `Σ_w X(w)` and today =
Today so far. The § 12.5.2 partition holds (`S ∩ O = ∅`, `S ∪ O = E`) with
identities 1–3 against `ArcSummary.daysElapsed`, `fullDays`,
`consistencyPercent` and `ArcHistory.perfectDays.total`; with no elapsed
day nothing is divided and the review shows no consistency. Checked by an
independent reference computed from the definitions:

- the worked XP examples A, B, C, D, E, F, G, G′, H and the 525-XP week
  boundary and before-start examples (exact figures);
- the day examples A, B, C, D′, D, E, F, G, H, I, J (exact figures);
- a seeded property test over 300 generated Arcs (Rolling with zero to
  five pauses, scheduled and open; Seasonal with late joins; active,
  completed and ended) and about 30 dates each, from before the start to
  after the end: every identity, settled dates only in reviewable weeks,
  and the strip's class agreeing with `ArcHistory.journey()` on every day.

Mutation checks (made and reverted locally): treating an ended Arc's
`closedOn` as open fails 9 tests; making the provider reconcile and sync
achievements fails the read-only gate and every provider test.

## Accessibility and layout

- One merged semantics node per stat, the Today block and each
  highlight, with every number in the label; the header is a semantics
  header in words; each day says its number, full date and state.
  Traversal order verified: header → summary → strip → stats → Today →
  highlights → habits.
- Day cells and week buttons: tap, Enter, Space (tested), focus
  highlight; upcoming and not-reached days are not buttons.
  `androidTapTargetGuideline`, `labeledTapTargetGuideline` and
  `textContrastGuideline` pass on the current, a complete and an ended
  week. Reduced motion: no frame scheduled once shown.
- Layouts (with a 40-character habit title), each scrolled top to bottom
  with no overflow: 360×800 @1×, 360×800 @2×, 320×568 @1.5×, 568×320,
  800×360 @1.3×, 1280×800, 360×640 @1.3× reduced motion; for the current,
  paused-pause-holding, paused, completed Week 13 and ended weeks, and the
  Journey header. Nothing scrolls sideways; cards ≤ 600 dp; day cells
  ≥ 48×48 dp; the strip is one line of 7 (Week 13: 7 + 1) at ≤ 1.3× text
  on ≥ 352 dp, else lines of 4.
- **Not performed in 12B:** TalkBack on a device and the emulator
  text-scale check (Phase 12H, spec A8/A2); widget tests use the square
  test font.

## Tests and CI

| File | Tests | Covers |
|---|---|---|
| `test/domain/arc_weeks_test.dart` | 25 | boundaries 1/7/8/14/84/85/91/92; 13 weeks; Rolling Wednesday start; Seasonal 2026; late join; before start; paused (also at a week boundary and inside Week 13); scheduled freeze; resume; several pauses; ended (on, after, before `closedOn`, Day 92); completed rollback; resolve; property |
| `test/domain/weekly_review_test.dart` | 40 | spec examples 1–7; Minimum Days; partial progress; zero opportunities; ledger-only XP; summit week; historic stability; strip = Journey; highlights (ties, exact ratios, thresholds, small samples); paused, resumed, ended, completed rollback; XP examples; day examples; property |
| `test/domain/weekly_summary_rules_test.dart` | 26 | all nine kinds and their priority; N = 0–3; 80/79/50/below; RECOVERY before MINIMUM; final, ended and in-progress Week 13; habit lines; paused; 100-run determinism; wording safety; exhaustive 4,096 three-day weeks and generated weeks against an independent oracle |
| `test/data/weekly_review_rollback_test.dart` | 9 | the rollback variants above; genuine format-1 and format-2 fixtures; a format-4 export with an ended and a paused Arc and a format-3 file (format 4 without its additions, the 12E1 convention: no genuine format-3 file is committed), restored and reviewed identically to the source, also behind the export date; nothing serialized |
| `test/features/weekly_review_provider_test.dart` | 6 | one `loadArc` per load; session lookups 2 / 1; no extra reads per week; no close-out or sync; refresh signals; failure and retry; superseded loads |
| `test/features/weekly_review_read_only_test.dart` | 1 | **merge gate**: every table (13, all populated) identical after each of 11 operations |
| `test/features/weekly_review_screen_test.dart` | 20 | entry points, routes, Back, no growing stack, no new tab, malformed weeks, every state, loading, error and retry, midnight, resume, strip, read-only detail, semantics order, keyboard, guidelines, reduced motion, source scan |
| `test/integration/weekly_review_layout_test.dart` | 42 | 7 layouts × 6 screens |
| `test/app/app_routes_test.dart` | +4 | review locations, guards, history binding, query parsing (including injection-like and overflowing values) |

CI: a new step in the "Format, analyze and test" job runs the eight new
files; every existing step is unchanged (the full suite still runs).

## Validation

All run locally in `~/labs/NextRep-12B` on the final tree (Flutter
3.47.5, JDK 21 for Gradle).

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| New Weekly Review tests (8 files) | 169 passed, 0 failed |
| `test/app/app_routes_test.dart` | 19 passed (4 new) |
| Migration tests (v1 → … → v7, 6 files) | 79 passed, 0 failed |
| Backup format tests (formats 1–4, 6 files) | 132 passed, 0 failed |
| `flutter test` (all) | **1588 passed, 0 failed** (1415 at Phase 12E1, plus 173: the 169 above and 4 route tests) |
| `flutter build apk --debug` / `--release` | both built (the release with the debug key: this worktree has no `key.properties`) |
| Native JVM (`:app:testDebugUnitTest`) | 71 / 71 passed |
| Release audit (CI's script, run locally) | exactly the expected permission set; no accessibility, VPN, notification-listener or foreground service; no in-app WebView; Focus Guard's provider present and not exported; R8 keeps WorkManager's and Focus Guard's constructors; package `com.nextrep.nextrep`, version `1.2.0` (3) |
| Exact-head CI | recorded in the PR description: it is checked on the final pushed head, which a later commit here would change |

No emulator or physical device was used, and no production signing key
was read: the worktree has no `android/key.properties`.

## Known limitations

- No emulator, TalkBack or device run in 12B (the brief asks for none; it
  is Phase 12H). Layouts were checked with the test font only.
- The `/arc/<active id>/review` redirect is covered by the pure
  `AppRoutes.redirect` test; the widget harness overrides the boot
  location, which skips the boot reconcile the redirect depends on.
- Nothing in the app creates a pause or an ended Arc yet (12E2, 12F);
  those reviews are reached through synthetic data and format-4 restores.
- The strip keeps the Journey's "Missed" label (12C, Gate C).

## Deferred

- The Arc Consistency Calendar (12C) will reuse `ArcWeeks` for its week
  headings and link them to these review routes.
- Freeze, Resume, Restart, deletion and sounds: 12E2, 12F, 12G.
