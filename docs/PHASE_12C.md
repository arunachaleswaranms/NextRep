# Phase 12C: Arc Consistency Calendar

## Objective and boundary

The second v1.3.0 user-facing feature: a **read-only** calendar of a
Winter Arc's 92 challenge days in its 13 Arc weeks, as a second layout of
the Journey. Built on the approved
[ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md) §§ 7–11 and the § 12
lifecycle addendum (which wins where they differ), the merged Phase 12E1
day ↔ date mapping ([PHASE_12E1.md](PHASE_12E1.md)) and the merged Phase
12B Arc weeks and Weekly Review ([PHASE_12B.md](PHASE_12B.md)).

Viewing the calendar stores, awards and sends nothing. No new state, day
classifier, route, tab, provider, query, table, migration, backup field,
permission, dependency or version. No Weekly Focus, widget, Freeze,
Resume, Restart, deletion, sound or release work. Version `1.2.0+3`; no
release; no physical phone; no production signing.

## Verified baseline

| | |
|---|---|
| `origin/main` | `f10fd75d5e1802e7ade26275d8d448bc10c6e2f7`, "Phase 12B: Weekly Arc Review (#25)", the expected baseline; nothing landed after it |
| PR #24 (12E1), PR #25 (12B) | both merged (14 and 18 Nov 2026) and on `main` |
| Schema | `AppDatabase.schemaVersion` 7 |
| Backup | `BackupDocument.formatVersion` 4 (reads 1–4) |
| Version | `1.2.0+3` |
| Existing 12C work | none: no branch, PR or worktree |
| Worktree | `~/labs/NextRep-12C`, new branch `phase/12c-v1.3-arc-calendar` from `f10fd75`; the primary checkout and the other worktrees were not touched |

## Architecture

```
Journey screen (existing, loads once)
  journeyControllerProvider / arcJourneyProvider → JourneyOverview
      ├── Path view (existing JourneyPath, unchanged)
      └── Calendar view (new ArcCalendarView)
            ArcCalendar.of(journey)                    pure, no I/O
              ├── journey.days (the 92 JourneyDays, by identity)
              ├── ArcWeeks.of(journey.session, journey.today)  (12B)
              └── journey.session.freezes → pause rows
            tap day      → DayDetailSheet.show / NotJoinedDaySheet (existing)
            tap heading  → AppRoutes.activeReview(w) / arcReview(id, w) (12B)
```

| File | Role |
|---|---|
| `lib/domain/journey/arc_calendar.dart` | **New.** `ArcCalendar`: 13 `CalendarWeek` blocks of `CalendarDay`s (each wraps the Journey's own `JourneyDay` and its `ArcWeekDay`), pause rows (`CalendarPause`), chapters starting in each week, settled and full-day counts, the initial week. Pure; throws if the Journey isn't 92 days or a date disagrees with its Arc week |
| `lib/features/journey/calendar_labels.dart` | **New.** Heading, date-range, chapter, pause and cell wording and their accessibility labels |
| `lib/features/journey/widgets/arc_calendar_view.dart` | **New.** `ArcCalendarView`: 13 lazy week blocks, headings, pause rows, sizing, initial week |
| `lib/features/journey/widgets/calendar_day_cell.dart` | **New.** `CalendarDayCell` (day number + glyph, the touch target) and `CalendarGlyph` (drawn from `JourneyDayStyle`), `calendarOutlineColor`, `calendarFillOpacity` |
| `lib/features/journey/journey_screen.dart` | The Path \| Calendar `SegmentedButton`; the Legend shows "Not reached" for an ended Arc |
| `lib/features/journey/widgets/journey_day_style.dart` | **Gate C copy only:** `missed` reads "No progress" |
| `.github/workflows/flutter-ci.yml` | A named "Calendar tests" step; every existing step unchanged |
| Tests | 7 new files, 1 new support file, 2 support helpers extended, 4 existing tests updated (below) |

## The Path | Calendar switch

A Material 3 `SegmentedButton` (Path, Calendar) in a fixed row under the
Journey header, on the Journey tab and on `/arc/:id/journey`. Path is
selected on every new screen; the choice is `State` of the Journey
screen, kept while it is open (including while a review is pushed over
it) and never stored. The two views share the one `JourneyOverview` the
screen already watches: an `IndexedStack` keeps the Path (and its scroll)
alive; the calendar is built the first time it's chosen and then kept.
Switching runs no provider, no query and no write. The header (back,
Legend, achievements, title, chapter, "Week N review", stats and level) is
the same in both views. No route, tab or setting was added; the four-tab
navigation is unchanged. The winter scene and reduced motion are
untouched.

## Zero-query data flow

`ArcCalendarView` receives the loaded `JourneyOverview` and computes
`ArcCalendar.of(journey)` in memory. The calendar code contains no
`Repository`, `Provider`, `ref.`, `loadArc`, `commitDay`, achievement,
reconcile, clock, database, network or platform reference (a source-scan
test forbids each). Full-day counts come from the Journey's states and
`ArcWeeks`' day classes, never from the Weekly Review provider or a second
`ArcHistory`. The Journey controller's own entry-point close-out check and
achievement sync are existing behaviour and run before the calendar
exists.

## The nine states

The calendar shows `JourneyDay.state` unchanged. The cell is the Journey's
own `JourneyDay` object (asserted by identity), so the two views cannot
disagree. Nine states (the eighth-state table of spec § 7.2 plus
`notReached` from § 12.4):

| State | Label | Glyph (from `JourneyDayStyle`) | Calendar outline |
|---|---|---|---|
| `notJoined` | Before you joined | circle, no fill, **dashed** | `textSecondary` (Journey: `outline`) |
| `notReached` | Not reached | circle, no fill | `textSecondary` (Journey: `outline`) |
| `future` | Upcoming | circle, no fill | `textSecondary` (Journey: `outline`) |
| `today` | Today | circle, no fill (accent tint) | `snow`, 3 dp |
| `perfect` | Perfect | circle, full, **star** | `accentSecondary` |
| `minimumComplete` | Minimum complete | **rounded square**, full, **flame** | `recovery` |
| `partial` | Partial | circle, half | `accentSecondary` |
| `minimumPartial` | Minimum partial | rounded square, half | `recovery` |
| `missed` | **No progress** (Gate C) | circle, no fill, **dash** | `textSecondary` |

Unlike Journey markers, every glyph is the same size (26 dp) inside an
equal cell, the day number is always shown above it (also for star, flame
and dash glyphs), and only the fill is ever dimmed: never the day number,
the outline, the label or the focus highlight. (Every dimmed state has no
fill, so in practice nothing is dimmed.) With the platform's high
contrast (`MediaQuery.highContrastOf`) fills are not dimmed at all. A
Minimum Day differs from a Perfect Day in shape, icon and label. A past
Minimum Day with no progress has the shared `missed` state and its detail
sheet still says "Mode: Minimum Day". Stored completions are never
re-scored.

**Today.** The cell whose `JourneyDay.isToday` is true gets the 3 dp
`snow` border and a static glow; its outcome state is kept (a Perfect or
completed Minimum Day today stays `perfect` / `minimumComplete` with the
border). An ended Arc has no `isToday` day, so its last day is never drawn
open, even on `closedOn`. A completed Arc viewed after a clock rollback
into it shows one open day, as approved (spec § 3.3, R22).

## 92 cells in 13 weeks

Week `w` is Days `7(w−1)+1 … 7w`; Week 13 is Days 85–92 (8 cells). No Week
14, no month grid, no Monday–Sunday or locale week. Season-day numbering
for Seasonal Arcs; Day 1 from the start date for Rolling Arcs. A pause
moves dates, never day numbers; an ended Arc still shows all 92 cells.

## Week headings and review links

`Week 3 · 15–21 Oct · 2 of 3 days full · This week ›`

- **Dates** from `WinterArcSession.dateOfDay` (via `ArcWeeks`): "15–21
  Oct"; "29 Oct – 4 Nov"; "28 Dec 2026 – 3 Jan 2027". An open pause:
  "8 Mar – paused", or "Dates are set when you resume" when no date of the
  week is known (12B's approved wording). Never an estimate.
- **Count:** settled days only, exactly the Weekly Review's `N` and `F`
  (full = Perfect or completed Minimum Day): never upcoming, today,
  before-joining, not-reached or paused dates. A reviewable week without a
  settled day reads "No finished days yet".
- **Status:** "· This week" for the week in progress, "· Paused" for the
  paused week; "Before you joined", "Not reached" and "Upcoming" replace
  the count for weeks that can't be reviewed.
- **Link:** a reviewable week (complete, in progress, paused) is a header
  button opening `AppRoutes.activeReview(w)` or, from Arc History,
  `AppRoutes.arcReview(id, w)`: the existing 12B screen. Back returns to
  the same Journey with the Calendar still selected. Other headings are
  plain headers: no button role, no "Opens the week review".
- **Chapters:** a week in which a chapter starts adds "First Ascent begins
  on Day 15" (`chapterTitle`, `JourneyChapter.firstDay`): Weeks 1, 3, 5,
  7, 9 and 11.

## Pauses and resumed Arcs

One text row per freeze interval, after the last challenge day before it
(`dayNumberOf(frozenFrom − 1)`), so it sits at the real boundary between
two days; never a cell, never a day number, never counted:

| Interval | Row |
|---|---|
| Resumed | "Paused 11–19 Mar · 9 days" (`[frozenFrom, resumedOn)`; the last paused date is `resumedOn − 1`) |
| Open, in effect | "Paused since 11 Mar" (no end date) |
| Open, still to come | "Pause starts 20 Mar" (today still counts) |

A pause right after a week's last day ends that week's block (once, not
duplicated). A pause inside Week 13 keeps its 8 cells. Several pauses each
appear once, in order. While a pause is open, later days are undated,
upcoming and not tappable ("Day 26. Upcoming. Its date is set when you
resume.").

## Ended and Completed Arcs, late Seasonal joins

- **Ended:** days after `closedOn` are `notReached` (not missed, not
  tappable, no record), whatever the device date; weeks after the
  `closedOn` week are "Not reached" and not reviewable; the last lived
  week is reviewable. Identical on `closedOn` and every later date; behind
  `closedOn` after a rollback, `closedOn` is upcoming (never missed). No
  Summit, no Today.
- **Completed:** every week complete with its final count; identical on
  any date after the end (tested at +1, +2, +90 and +800 days).
- **Late Seasonal join (Day 18):** Days 1–17 are `notJoined`: dashed,
  visible, open the existing note ("You joined on Day 18. Earlier season
  days are not counted against you."), never counted; Weeks 1–2 "Before
  you joined"; Week 3 mixes neutral and participating days. The Journey
  header keeps "Joined on Day 18. Earlier days don't count against you."
  above both views.

## Day details

Past days and today open the existing read-only `DayDetailSheet`; days
before joining open `NotJoinedDaySheet`; upcoming, undated and not-reached
days are not buttons and do nothing. No edit control, logging, XP, goal or
mode change is reachable (asserted: no text field, checkbox, switch or
button in the sheet).

## Initial scroll

The calendar opens with `ArcWeeks.defaultWeek` at the top: the week in
progress, else the paused week, else the latest reviewable week (Week 13
of a completed Arc, the `closedOn` week of an ended Arc). Before the
participation start (nothing reviewable) it opens on the join week. It is
a `CustomScrollView` whose `center` is that week's lazy sliver (earlier
weeks in a lazy sliver growing upwards), so the position is instant with
no measuring and no animation. One post-frame jump fills the view with the
weeks above when the rest is shorter than the screen (Week 13). The
initial week is fixed for the life of the view: a refresh or midnight
never moves what the user is looking at (tested). Week 1 and Week 13 are
always reachable.

## Accessibility

- Cells: one merged node, e.g. "Day 18, Sunday 18 October. Today. 40
  percent complete." / "Day 8, Thursday 8 October. Before you joined this
  Seasonal Winter Arc." / "Day 43. Not reached."; a button (tap, Enter,
  Space, focus highlight) only where a sheet opens. The label is the
  Weekly Review strip's for the same day (property-tested).
- Headings: header nodes, e.g. "Week 3 of 13, 15 to 21 October, 2 of 3
  days full, this week. Opens the week review."; the action only when
  reviewable. Pause rows: their sentence.
- Order (tested in the real app): the switch → Week 1 heading → its
  chapter line → its days in Arc order with the pause row in place → Week
  2 heading … → Day 92. One `FocusTraversalGroup` (reading order) per week.
- Touch targets ≥ 48 × 48 dp; `androidTapTargetGuideline`,
  `labeledTapTargetGuideline` and `textContrastGuideline` pass on active,
  paused, ended and late-joined Calendars.
- Reduced motion: no frame is scheduled once shown.
- **Not performed:** TalkBack on a device or emulator (Phase 12H, A8).

## Contrast measurements

Computed in a unit test from `WinterColors.night` against the calendar's
opaque `surface` (#111A2E), which every week block is drawn on (WCAG
relative luminance; the test computes the ratios and asserts the minimums,
nothing is hard-coded; the figures below are the same formula on the token
values):

| Use | Token | Ratio vs `surface` | Needed |
|---|---|---|---|
| Upcoming / before joining / not reached / no-progress outline, dash | `textSecondary` | 6.20 | 3 |
| Perfect, partial outline; chapter line | `accentSecondary` | 10.99 | 3 / 4.5 |
| Minimum outlines | `recovery` | 8.55 | 3 |
| Today border, today's number | `snow` | 14.72 | 3 / 4.5 |
| Day numbers, headings, pause rows | `textPrimary` | 16.02 | 4.5 |
| Unreviewable headings | `textSecondary` | 6.20 | 4.5 |
| Star / flame on their fill | `background` on `accentSecondary` / `recovery` | 12.43 / 9.68 | 3 |
| Pause icon | `fog` | 9.01 | 3 |
| The Journey's `outline` token (why it isn't used) | `outline` | 1.44 | — |

Every outline is drawn at full opacity. The Journey Path and Weekly
Review keep their colours (no regression).

## Layout results

`test/integration/calendar_layout_test.dart`: 7 layouts × 5 Arcs = 35
runs, all passing: 360×800 @1×, 360×800 @2×, 320×568 @1.5×, 568×320,
800×360 @1.3×, 1280×800, 360×640 @1.3× reduced motion; an active Arc with
a resumed pause and a 40-character habit, a paused Arc (undated days), a
completed Arc, an ended Arc and a late-joined Seasonal Arc. Each calendar
is scrolled from Week 1 to Week 13 (all 13 headings reached); no overflow
or exception; nothing scrolls sideways; rows ≤ 600 dp; every on-screen cell
≥ 48 × 48 dp; a week is one line of 7 (Week 13: 7 + 1) at ≤ 1.3× text on
≥ 352 dp, else lines of 4 (Week 13: 4 + 4); no heading hits a line limit.
The Legend and today's detail (with the 40-character title) are opened and
scrolled on every layout. The 12B sweep's "Journey header" case covers the
header with the new switch on the same layouts.

## Read-only proof

`test/features/calendar_read_only_test.dart` (merge gate): real in-memory
Drift with all 13 tables populated, the real app and the real Journey
screen. The Journey loads and its own close-out check and achievement sync
finish; **then** every row and column of every table is captured. After
each step every table must equal the capture and no repository write may
be counted: Path → Calendar; scrolling to Weeks 1, 13 and back; opening
and dismissing several day details; a before-joining note; a week review
from its heading; Back; Calendar → Path; Path → Calendar. Repeated for the
active Arc, a completed Arc, an ended Arc, a paused Arc and a late-joined
Seasonal Arc. All pass. `test/data/calendar_restore_test.dart` restores a
format-4 backup with an ended and a paused Arc and shows identical
calendars to the source on four dates (two behind the export date), with
nothing written.

## Zero extra queries

`test/features/calendar_navigation_test.dart` counts every repository
call (progress `loadArc` and other reads, session lookups, achievement
reads and writes). After the Journey has loaded, switching Path ↔
Calendar five times and scrolling to Weeks 1 and 13 adds **0** `loadArc`,
**0** other progress reads, **0** session lookups, **0** achievement reads
and **0** writes. In the read-only gate the only read after the capture is
the Weekly Review's own single `loadArc` when its route is opened.

**Mutation checks** (made and reverted locally): making the switch
re-load the Journey fails the zero-read test and three read-only tests;
counting a Minimum partial day as full fails the Weekly Review agreement
test.

## Tests

| File | Tests | Covers |
|---|---|---|
| `test/domain/calendar_state_test.dart` | 32 | 92 cells / 13 blocks / 7 + 8 / no Week 14; Seasonal 2026 Thursdays; Rolling across a year; leap year and DST; identity with the Journey; every state; Today with Perfect and Minimum outcomes; goal edits; full-day counts = Weekly Review for generated Arcs; late join; initial week; resumed, boundary, Week 13, several, open and scheduled pauses; ended Arcs on, after and behind `closedOn`; completed Arcs at several dates and after a rollback; **property test** over 150 generated Arcs × their dates (2,000+ calendars); wording; Gate C copy; A6 distinctness; A12 contrast; high contrast |
| `test/data/calendar_restore_test.dart` | 1 | format-4 ended and paused Arcs restored; identical calendars; read-only |
| `test/features/arc_calendar_test.dart` | 12 | rendering, equal cells, day numbers, Week 13 wrap, 7 / 4 per line at the boundaries, glyph tuples and outlines, Today border, taps and sheets, heading links (active, historical, none), pause rows, initial scroll and fill, refresh keeps scroll, high contrast and reduced motion, keyboard, worst-case build |
| `test/features/calendar_navigation_test.dart` | 8 | Path default, no persistence, no route or tab, zero extra reads, review links and Back (active, completed, ended), unreviewable headings, paused Arc, Legend in both views, read-only day sheets |
| `test/features/calendar_read_only_test.dart` | 4 | the merge gate (5 Arcs) and a source scan |
| `test/features/calendar_accessibility_test.dart` | 4 | all nine announcements and roles, focus groups and headers, reading order, guidelines |
| `test/integration/calendar_layout_test.dart` | 35 | the layout sweep |

Property state equality, for every day 1–92 of every generated calendar:
`dayNumber`, `date`, `state`, `isToday`, record completion and mode equal
a second, independent `ArcHistory.journeyDay(n)`; the cell is the
Journey's `JourneyDay` by identity; the date is `dateOfDay(n)` (null after
an open pause, never guessed); no cell is a paused date; the day class
agrees with the Journey state; each day is in exactly one block; each
pause appears exactly once, between the right two days; blocks are
7 × 12 + 8. Seeds are fixed (`20261119`, `1219`, `5`).

**Existing tests updated, legitimately:**

- `phase3_flow_test`, `phase7_accessibility_test`,
  `journey_ended_arc_test`: the announcement "Day N. Missed." is now "Day
  N. No progress." (Gate C copy). Nothing else changed.
- `phase6_flow_test`: the Path's viewport is 56 dp shorter (the switch
  row), and its drag's fling carried a marker past the edge; the test now
  calls `ensureVisible` before tapping, as its own `_tapVisible` helper
  already does. No assertion changed.
- `test/support/review_app.dart` accepts counting session and achievement
  repositories.

## Validation

All run locally in `~/labs/NextRep-12C` on the final tree (Flutter
3.47.5, JDK 21 for Gradle).

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean (351 files, 0 changed) |
| `flutter analyze` | no issues |
| Calendar tests (7 files) | 96 passed, 0 failed |
| Weekly Review tests (8 files) | pass (part of the full run) |
| `flutter test` (all) | **1684 passed, 0 failed** (1588 at Phase 12B, plus the 96 above) |
| `flutter build apk --debug` / `--release` | both built (the release with the debug key: this worktree has no `key.properties`) |
| Native JVM (`:app:testDebugUnitTest`) | 71 / 71 passed |
| Release audit (CI's script, run locally) | exactly the expected permission set; no accessibility, VPN, notification-listener or foreground service; no in-app WebView; Focus Guard's provider present and not exported; R8 keeps WorkManager's and Focus Guard's constructors; package `com.nextrep.nextrep`, version `1.2.0` (3) |
| Exact-head CI | recorded in the PR description: it is checked on the final pushed head, which a later commit here would change |

Worst-case build (12 habits with 40-character titles, a revision every
other day per habit, three resumed pauses, every day logged): the Journey
model in 1 ms and the calendar's first build and layout in 44 ms, in a
debug-mode widget test (not a profile build; recorded, not gated). No
emulator or physical device was used, and no production signing key was
read: the worktree has no `android/key.properties`.

## Gate C: the "Missed" wording (APPROVED)

**Proposal (spec § 7.2, recommended):** the Journey state labelled
"Missed" is shown as **"No progress"**.

| | Before | Proposed |
|---|---|---|
| State label (`JourneyDayStyle.label`) | Missed | **No progress** |
| Announcement (`journeyDayLabel`) | "Day 6. Missed." | **"Day 6. No progress."** |
| Calendar announcement | — | "Day 7, Thursday 15 October. No progress." |
| Day detail heading | MISSED | **NO PROGRESS** |

Shared consumers: Journey Path, Calendar, the Legend, the Weekly Review
day strip, the day detail sheet and every accessibility description. The
Dart state stays `JourneyDayState.missed`; its classification, precedence,
stored data, Minimum Day records, progress flags, XP, achievements and
streaks are unchanged; no migration.

**New Calendar wording, for the same sign-off:** "Path", "Calendar";
headings "Week 3 · 15–21 Oct · 2 of 3 days full", "· This week", "·
Paused", "No finished days yet", "Before you joined", "Not reached",
"Upcoming"; chapter lines "First Ascent begins on Day 15"; pause rows
"Paused 11–19 Mar · 9 days", "Paused since 11 Mar", **"Pause starts 20
Mar"** (a scheduled pause: no approved wording existed; "Paused since"
would name a future date); cell labels above; heading labels "… Opens the
week review."

**Decisions taken in 12C (for review):**

1. "x of y days full" counts settled days for `y` (spec §§ 4.2, 7.3), as
   the Weekly Review's consistency does, not the week's length.
2. A heading doesn't repeat "· includes a 9-day pause" (the review
   header's § 12.3 wording): the pause row says it in place.
3. A not-reached cell names no date: its planned date was never lived.
4. Before the participation start the calendar opens on the join week.

### Gate C outcome

**APPROVED by the owner on 19 November 2026.** The owner formally
approved Gate C for the implementation at `db1f40c` (PR #26; CI run
[44377903117](https://github.com/arunachaleswaranms/NextRep/actions/runs/44377903117)
green on that head, both jobs), including:

1. "No progress" replacing the user-facing "Missed" label;
2. "Pause starts [date]" for a scheduled pause;
3. "No finished days yet" for a reviewable week with no settled days;

and all the other Calendar wording documented above. No wording changed
with the approval. The owner also reported that the independent technical
review of PR #26 passed. The PR stays unmerged pending one final
independent verification; the owner merges it.

## Known limitations

- No emulator, TalkBack or device run (Phase 12H). Layouts were checked
  with the test font only.
- The Path's visible area is 56 dp shorter because of the switch row.
- The segments' words are child nodes of Material's segment buttons
  (standard `SegmentedButton` semantics); TalkBack reads them with the
  button.
- Nothing in the app creates a pause or an ended Arc yet (12E2, 12F);
  those calendars are reached through synthetic data and format-4
  restores.
- The view choice resets whenever the Journey screen is rebuilt from
  scratch (by design: not persisted).

## Deferred

- Freeze and Resume (12E2) will create the pause rows shown here; Restart
  (12F) the ended Arcs.
- TalkBack and emulator text-scale checks: 12H. Release qualification:
  12I.
