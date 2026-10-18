# NextRep v1.3.0 roadmap: Arc Momentum

Planned in Phase 12A ([PHASE_12A.md](PHASE_12A.md)). Feature rules are in
[ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md). This roadmap is a plan.
**v1.3.0 is not released.** The published release is v1.2.0 (`1.2.0+3`).

## Product objective

v1.2.0 helps users stay on track (reminders, Hydration Coach, Focus
Guard). v1.3.0 helps them **understand** their progress and build
consistency:

1. How am I doing?
2. Where am I struggling?
3. What should I focus on next?

It must feel like part of the Winter Arc, stay fully offline, and add no
accounts, servers, social features, analytics or AI.

## Scope

### Guaranteed

| Feature | Phase | Summary |
|---|---|---|
| **A. Weekly Arc Review** | 12B | Per Arc week (13 weeks; Week 13 = Days 85–92): habit completion, consistency, XP from the ledger, Perfect and Minimum Days, Most consistent and Room to grow, and one deterministic supportive summary. Read-only. |
| **B. Arc Consistency Calendar** | 12C | A Path / Calendar switch in Journey: 92 days in 13 week blocks, using Journey's existing day states. Read-only. Taps open the existing day sheets. |

Neither guaranteed feature depends on a conditional one. Both need **no
schema change, no migration and no backup-format change**
([PHASE_12A.md § H](PHASE_12A.md#h-data-model-findings)).

### Conditional (Phase 12A verdicts)

| Feature | Verdict | Why | Revisit |
|---|---|---|---|
| C. Weekly Focus | **DEFER** | The only candidate that needs schema v7 + backup format 4, which v1.2 can't read. Its value is mostly covered by the review's derived "Room to grow". | v1.4 planning |
| D. Android home-screen widget | **DEFER** | Feasible read-only and without permissions, but needs native Kotlin, an exported receiver, release-audit changes and a launcher × Android-version physical matrix. | a v1.4 feasibility phase with a debug-only probe |

The owner may override either verdict at Gate A. If Weekly Focus were
approved, it would add a 12D implementation phase with its own migration
and backup work (outline in
[PHASE_12A.md § I](PHASE_12A.md#i-feature-c-weekly-focus-feasibility--defer)).
The widget never joins v1.3.

### Out of scope for v1.3.0

New achievements; any XP, streak, Perfect Day or Minimum Day rule change;
new notifications (including a "your review is ready" reminder); sharing a
weekly review as a card; calendar months view; Today-screen review card;
accounts, cloud sync, analytics, telemetry, AI or any new network request;
new Android permissions or dependencies; iOS release; store publication;
everything already listed as explicitly deferred in the README.

## Phase plan

### 12A: planning, architecture and feasibility (this PR)

Documentation only: [PHASE_12A.md](PHASE_12A.md),
[ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md), this roadmap and a
PROJECT_STATE entry. No production code, device, version, APK or release.

### 12B: Weekly Arc Review

- `lib/domain/journey/arc_weeks.dart` (`ArcWeeks`). Shared with 12C, so
  built first.
- `lib/domain/review/weekly_review.dart` (`WeeklyReview.fromHistory`) and
  `weekly_summary_rules.dart`: spec § 3, § 4, § 6.
- `lib/features/review/`: controller, screen, summary text, week strip.
  "Week N review" button in the Journey header; routes
  `/journey/review?week=N` (root navigator) and `/arc/:id/review?week=N`.
- Tests: [PHASE_12A.md § L1](PHASE_12A.md#l1-weekly-review-12b) (unit,
  property, repository with the restored fixtures, widget, routes,
  accessibility).
- Exit: spec § 11 R1–R8; owner copy sign-off on the summary text; CI green;
  independent review; owner merge.

### 12C: Arc Consistency Calendar

- `lib/features/journey/widgets/arc_calendar.dart`,
  `calendar_day_cell.dart`, `calendarDayLabel`; the Path / Calendar switch
  in `journey_screen.dart`; week headings link to 12B's review.
- No new domain classifier: renders `JourneyDay.state`.
- Tests: [PHASE_12A.md § L2](PHASE_12A.md#l2-calendar-12c).
- Exit: spec § 11 K1–K6; the "Missed" wording decision (Q4); CI green;
  review; merge.

### 12D: Arc Momentum hardening (Weekly Focus deferred)

Weekly Focus is deferred, so 12D is a **bounded, non-feature** phase.
Nothing new for users:

1. A copy and tone pass over every new string against the spec's
   forbidden-word list, with owner sign-off.
2. Edge-case hardening found while building 12B / 12C: seasonal late join
   on Day 92, a time-zone change across a week boundary, restore of a
   completed-Arc backup, then the review.
3. Automated performance guards: query-count tests and a large-Arc build
   test (12 habits × 92 days, heavy revisions). Emulator profiling stays
   in 12E.
4. Automated accessibility: semantics-tree, tap-target and contrast tests
   on both screens, plus the 1× layout added to the sweep. Emulator
   TalkBack and the 2× / 360 dp device check stay in 12E.
5. Documentation: README features, CHANGELOG "Unreleased" entry, PRIVACY
   (it states that nothing new leaves the device).

If the owner approves Weekly Focus at Gate A, 12D becomes its
implementation phase instead (schema v7, backup format 4, the tests in
[PHASE_12A.md § L3](PHASE_12A.md#l3-weekly-focus-only-if-approved-later-not-planned-for-v13)),
and the hardening items move into 12E.

### 12E: cross-feature integration and regression

- Weekly Review, Calendar, Insights, Journey and historic Arcs working
  together: the same numbers everywhere they overlap (the spec § 4.5
  reconciliation against Insights and the Arc summary; exact for completed
  Arcs, and with today's term for the active Arc).
- Emulator qualification: TalkBack reading order, 2× / 360 dp on the
  device font, reduced motion, midnight with a screen open, and a
  profile-build timing of the review and calendar (recorded, not gated).
  Layout sweep extended to both new screens. Backup compatibility (formats
  1 / 2 / 3 restore, then review and calendar).
- Full v1.2 regression (PHASE_12A § L5): Hydration Coach, Focus Guard,
  reminders, the update check, backup / restore, migrations, achievements,
  Journal.
- No widget work in 12E (deferred). No new features. Defects fixed with
  tests.

### 12F: v1.3.0 release qualification

- Version bump to **`1.3.0+4`** (the only phase that changes the version).
- Full automated suite, native JVM tests, focused suites; format and
  analyze clean.
- Signed release candidate with the **permanent key** in the main checkout
  only (never printed or committed), certificate SHA-256
  `65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba`;
  package `com.nextrep.nextrep`.
- Exact permission audit: the same 7 permissions as v1.2.0, and the same
  merged components.
- Reproducibility: byte-identical across two clean builds.
- Signed v1.2.0 → v1.3.0 `adb install -r` rehearsal on a disposable AVD
  with synthetic data; every table identical before and after (schema stays
  v6, no migration runs).
- Physical OnePlus signed in-place upgrade **only after explicit owner
  authorization**: backup first, data preservation compared, smoke of the
  review and calendar plus the v1.2 features.
- Release notes `docs/releases/v1.3.0.md`; README, CHANGELOG, PRIVACY,
  DIRECT_DISTRIBUTION, RELEASE_CHECKLIST (a fresh v1.3.0 section),
  PROJECT_STATE.
- Independent PR review → owner merge → **separate publication
  authorization** → tag `v1.3.0`, draft with the APK and `.sha256`,
  verified, published; unauthenticated public verification and
  `releases/latest`.

## Dependencies

```
12A ──Gate A──► 12B ──► 12C ──► 12D ──► 12E ──► 12F ──Gate G──► publish
                 │        ▲
                 └ArcWeeks┘   (12C reuses 12B's ArcWeeks and links to its review)
```

- 12C depends on 12B only for `ArcWeeks` and the review route. Both are
  guaranteed. If 12B slipped, 12C could still ship by building `ArcWeeks`
  itself and leaving the week headings unlinked.
- Nothing guaranteed depends on Weekly Focus or the widget.

## Approval gates

| Gate | When | Owner decides |
|---|---|---|
| **A** | after this PR's independent review | Arc-week model (D1); metric naming (D2); Weekly Focus **DEFER**; widget **DEFER**; merge 12A |
| **B** | end of 12B | summary copy sign-off; merge |
| **C** | end of 12C | "Missed" wording; merge |
| **D** | end of 12D | hardening results; merge |
| **E** | end of 12E | integration verdict; go to release qualification |
| **F** | during 12F | authorization for the physical OnePlus signed upgrade; then independent review and merge |
| **G** | after 12F merge | separate publication authorization (tag, GitHub Release) |

No phase merges itself. Every PR waits for independent review and the
owner's merge.

## Release safety rules (all phases)

- **Identity:** package `com.nextrep.nextrep`; the permanent signing
  certificate (above); no key rotation; no new application id; no
  temporary suffix in source.
- **Data:** every Arc, habit, revision, progress row, XP entry, streak,
  achievement, reflection, reminder, Hydration and Focus Guard setting
  survives the upgrade. No destructive migration, no reset. Schema stays
  **v6**; backup stays **format 3** (reads 1 / 2 / 3). v1.0.0 / v1.1.0 /
  v1.2.0 backups keep restoring.
- **Rules:** no change to Arc dates, habit limits, goal-edit timing,
  Minimum Day, Perfect Day, XP, streaks, levels or the 32 achievements.
  Viewing a review or the calendar writes nothing.
- **Privacy:** no new permission, dependency or network request; no
  analytics, telemetry, accounts or cloud.
- **Distribution:** no automatic update installation. Signing only on the
  owner's machine. Physical device work only with explicit authorization.
  Publication only with separate authorization.
- **Process:** one PR per phase; CI green on the final head; independent
  review; owner merge.
