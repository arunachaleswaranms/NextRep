# NextRep v1.3.0 roadmap: Arc Momentum

Planned in Phase 12A ([PHASE_12A.md](PHASE_12A.md)) and expanded by the
Phase 12A Addendum ([PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md)).
Feature rules are in [ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md) and
[ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md). This roadmap is a plan.
**v1.3.0 is not released.** The published release is v1.2.0 (`1.2.0+3`).

**Status of this revision:** the expanded scope and phase plan below are
**proposed**. They replace the Phase 12A allocation only when the owner
approves them at Gate A2. Until then no implementation phase starts.

## Product objective

v1.2.0 helps users stay on track (reminders, Hydration Coach, Focus
Guard). v1.3.0 helps them **understand** their progress and **shape**
their Arc:

1. How am I doing? Where am I struggling? What should I focus on next?
   (Arc Momentum: Weekly Review, Calendar.)
2. Can I arrange it, prepare it, pause it and begin again on my terms?
   (Arc Control: ordering, saved setup, Freeze, Restart, sounds.)

It must feel like part of the Winter Arc, stay fully offline, and add no
accounts, servers, social features, analytics or AI.

## Scope

### Planned features

| Feature | Phase | Summary | Schema / backup |
|---|---|---|---|
| **A. Weekly Arc Review** | 12B | Per Arc week (13 weeks; Week 13 = Days 85–92): habit completion, consistency, ledger XP, Perfect and Minimum Days, highlights, one deterministic summary. Read-only | reads only |
| **B. Arc Consistency Calendar** | 12C | A Path / Calendar switch in Journey: 92 days in 13 week blocks, Journey's day states. Read-only | reads only |
| **1. Habit ordering in setup** | 12D | Drag, or Move up / Move down, to order the habits of an Arc in setup. The order is the Arc's order | none (`sort_order` exists) |
| **2. Saved setup and start confirmation** | 12D | The setup is saved as it is edited. A hub on reopening (Continue Editing, Review Setup, Start Challenge) and an explicit Confirm & Start. Day 1 is the confirmation date | none (the `setup` session exists) |
| **3. Freeze / Resume** (Rolling only) | 12E1 + 12E2 | A real pause from the next day: paused dates are not days of the Arc; the day count continues on resume and the last day moves later. Never for Seasonal Arcs | `arc_freezes` table |
| **4. Restart** | 12F | A new Day 1 Arc with the same habits, goals and order, after typing RESTART. The old Arc is kept as "Ended early". Optional, separately confirmed deletion of the old Arc | status `ended`, `closed_on` column |
| **5. Completion sounds** | 12G | A short local sound on a real completion; three original sets; a switch in Settings; quiet on a silenced phone | `feedback_preferences` table |

**v1.3.0 is a migration release** under this plan: database **schema v7**
(additive) and **backup format 4** (write 4, read 1–4). The verdict "no
migration" in Phase 12A was for features A and B alone, which still need
none ([PHASE_12A_ADDENDUM.md § G](PHASE_12A_ADDENDUM.md#g-schema-v7-proposed-additive),
[§ H](PHASE_12A_ADDENDUM.md#h-backup-format-4-proposed)).

### Deferred (Phase 12A verdicts, unchanged)

| Feature | Verdict | Revisit |
|---|---|---|
| Weekly Focus | **DEFER** ([PHASE_12A.md § I](PHASE_12A.md#i-feature-c-weekly-focus-feasibility--defer)) | v1.4 planning |
| Android home-screen widget | **DEFER** ([PHASE_12A.md § J](PHASE_12A.md#j-feature-d-android-home-screen-widget-feasibility--defer)) | a v1.4 feasibility phase |

### Out of scope for v1.3.0

New achievements; any XP, streak, Perfect Day or Minimum Day rule change;
new kinds of notification (including "your review is ready", "start your
saved setup" and "still paused"); Freeze for Seasonal Arcs; reordering in
a running Arc; more than one saved setup; preparing the next Arc while
one runs; a maximum pause or automatic resume; partial deletion of an
Arc; sounds for level-ups or achievements; an in-app volume control;
sharing a weekly review; a months view; accounts, cloud sync, analytics,
telemetry, AI or any new network request; new Android permissions; any
new dependency; iOS release; store publication.

## Phase plan

The owner proposed 12B Review, 12C Calendar, 12D ordering and saved
setup, 12E Freeze, 12F Restart, 12G Sounds, 12H integration, 12I release.
That allocation is kept, with one change recommended from the source
(addendum decision AD18): **12E is split, and its foundation half runs
first.** The Weekly Review and Calendar compute dates from the session;
if they were built before Freeze changed that computation, both would be
built twice.

**Recommended order:**
`12E1 → 12B → 12C → 12D → 12E2 → 12F → 12G → 12H → 12I`

### 12A Addendum: design (this PR)

Documentation only: [PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md),
[ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md), § 12 of
[ARC_MOMENTUM_SPEC.md](ARC_MOMENTUM_SPEC.md), this roadmap and a
PROJECT_STATE entry. No production code, device, version, APK or release.

### 12E1: lifecycle foundation (no visible feature)

- Schema **v7**, one additive step: `arc_freezes`,
  `winter_arc_sessions.closed_on`, `feedback_preferences`; a new schema
  snapshot and `migration_v7_test`.
- Backup **format 4**: write 4, read 1–4; validation rules of addendum
  § H.
- Status value `ended`; `WinterArcSession` gains `freezes` and
  `closedOn`, and the day ↔ date mapping (`dateOfDay`, freeze-aware
  `dayNumberOf`, `isParticipatingOn`, `participatingDatesThrough`,
  `isOverOn`).
- Every existing reader moved onto the mapping
  ([addendum § F1](PHASE_12A_ADDENDUM.md#f1-the-sessions-day--date-mapping-proposed)),
  and every status comparison reviewed
  ([§ F2](PHASE_12A_ADDENDUM.md#f2-sites-that-test-the-status)).
- Focus Guard's native schema gate moved from 6 to 7, with its JVM tests.
- **No screen changes.** Nothing can create a freeze or an ended Arc yet.
- Exit: with no freeze rows, every reader returns exactly what v1.2.0
  returns (property tests); v6 → v7 leaves every v6 row identical;
  formats 1–3 restore; Focus Guard runs after an emulator upgrade; CI
  green; review; merge.

### 12B: Weekly Arc Review

As planned in Phase 12A ([spec §§ 3–6](ARC_MOMENTUM_SPEC.md#3-the-nextrep-week-proposed-decision-d1),
tests [PHASE_12A.md § L1](PHASE_12A.md#l1-weekly-review-12b)), built on
`dateOfDay`, plus the paused and ended states of
[spec § 12](ARC_MOMENTUM_SPEC.md#12-lifecycle-addendum-freeze-and-restart)
(tested with sessions built in tests; no UI can create them yet).

- Exit: spec § 11 R1–R8 and § 12.8 R9–R16 (including the XP split for
  every Arc status, addendum § L7 F3); owner copy sign-off; CI green;
  review; merge.

### 12C: Arc Consistency Calendar

As planned ([spec § 7](ARC_MOMENTUM_SPEC.md#7-arc-consistency-calendar-proposed-decisions-d5d6),
tests [PHASE_12A.md § L2](PHASE_12A.md#l2-calendar-12c)), plus the pause
row and the `notReached` state (spec § 12.4).

- Exit: spec § 11 K1–K6 and § 12.8 K7; the "Missed" wording decision;
  CI green; review; merge.

### 12D: habit ordering, saved setup, start confirmation

- `HabitRepository.reorderSetupHabits`; drag and Move up / Move down in
  Habit Setup.
- The saved-setup hub (`/setup/saved`), Review Setup, Confirm & Start,
  "Save for Later"; settings links from the hub.
- No schema or backup change.
- Exit: [ARC_CONTROL_SPEC.md § 10](ARC_CONTROL_SPEC.md#10-acceptance-criteria)
  O1–O5 and S1–S7; tests of addendum § L2; CI green; review; merge.
- 12D depends on nothing in 12E1 and can be scheduled anywhere after
  Gate A2. It is the lowest-risk phase.

### 12E2: Freeze and Resume

- Freeze service and repository writes; the Pause sheet, scheduled
  banner, frozen screen and Resume sheet; reminder re-planning; paused
  days in the Arc summary and Arc History.
- Exit: spec § 10 Z1–Z12; tests of addendum § L3 and § L7 (F1);
  emulator checks (midnight, kill, reboot, notifications); CI green;
  review; merge.

### 12F: Restart and optional deletion

- The atomic end-and-start transaction; the typed RESTART flow; "Ended
  early" in History, Summary, Journey, reviews and Insights; the separate
  typed DELETE screen; deletion extended to ended Arcs.
- Exit: spec § 10 T1–T11; tests of addendum § L4 and § L7 (F2); CI
  green; review; merge.

### 12G: completion sounds

- Three original sound sets (six short files, source committed); the
  native player behind a Dart interface; the trigger and throttle; Sound
  & Feedback settings.
- Exit: spec § 10 N1–N7; tests of addendum § L5; emulator check of
  silent, vibrate, Do Not Disturb and music playing; owner listening
  sign-off on the sounds; CI green; review; merge.

### 12H: integration, accessibility, migration and regression

The former 12D hardening and 12E integration phases, over the whole
release:

- All seven features together: the same numbers wherever they overlap
  (spec § 4.5 and § 12.5); the combined flow saved setup → start →
  review → freeze → resume → restart → delete.
- Copy and tone pass over every new string, with owner sign-off.
- Layout sweep extended to every new screen; emulator TalkBack reading
  order, 2× / 360 dp, reduced motion, midnight with each screen open;
  profile timings (recorded, not gated).
- Migration and backup: v1 → v7 chain; formats 1–4; restore then every
  feature.
- Full v1.2 regression ([PHASE_12A.md § L5](PHASE_12A.md#l5-release-regression-12e-12f)).
- README, CHANGELOG "Unreleased", PRIVACY (sounds are local; nothing new
  leaves the device).
- No new features. Defects fixed with tests.

### 12I: v1.3.0 release qualification

- Version bump to **`1.3.0+4`** (the only phase that changes the
  version).
- Full automated suite, native JVM tests, focused suites; format and
  analyze clean.
- Signed release candidate with the **permanent key** in the main
  checkout only (never printed or committed), certificate SHA-256
  `65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba`;
  package `com.nextrep.nextrep`.
- Exact permission audit: the same 7 permissions as v1.2.0 and the same
  merged components.
- Reproducibility: byte-identical across two clean builds.
- Signed v1.2.0 → v1.3.0 `adb install -r` rehearsal on a disposable AVD
  with synthetic data: a **real v6 → v7 migration**, every v6 row
  identical afterwards, a format-3 backup exported before and restored
  after, Focus Guard's natural run after the upgrade.
- Physical OnePlus signed in-place upgrade **only after explicit owner
  authorization**: backup first, data preservation compared, smoke of
  every new feature including sounds on silent and with the ringer on.
- Release notes `docs/releases/v1.3.0.md` (including: v1.3 backups can't
  be restored into v1.2); README, CHANGELOG, PRIVACY,
  DIRECT_DISTRIBUTION, RELEASE_CHECKLIST (a fresh v1.3.0 section),
  PROJECT_STATE.
- Independent PR review → owner merge → **separate publication
  authorization** → tag `v1.3.0`, draft with the APK and `.sha256`,
  verified, published; unauthenticated public verification and
  `releases/latest`.

## Dependencies

```
12A Addendum ─Gate A2─► 12E1 ─► 12B ─► 12C ─► 12D ─► 12E2 ─► 12F ─► 12G ─► 12H ─► 12I ─Gate P─► publish
```

| Phase | Needs | Why |
|---|---|---|
| 12E1 | Gate A2 | the storage and mapping design is approved there |
| 12B | 12E1 | week dates come from `dateOfDay` |
| 12C | 12E1, 12B | `ArcWeeks` and the review route; `notReached` |
| 12D | Gate A2 only | no schema or mapping dependency |
| 12E2 | 12E1 | intervals and mapping exist; (12B, 12C so their paused states can be checked end to end) |
| 12F | 12E1, 12E2, 12D | `ended` and `closed_on`; must handle a frozen Arc; reuses the review wording |
| 12G | 12E1 | the settings table |
| 12H | all of the above | |
| 12I | 12H | |

## Staged alternative

If 12E1 or 12E2 slips or fails qualification, the release can be staged
without redesign. This is a fallback, not the plan, and it removes no
feature from the target.

| Release | Contents | Schema / backup |
|---|---|---|
| **v1.3.0** | Weekly Review, Calendar, habit ordering, saved setup and start confirmation | v6 / format 3 (no migration) |
| **v1.4.0** | Freeze / Resume, Restart and deletion, completion sounds | v7 / format 4 |

In the staged form, 12B and 12C still go through a `dateOfDay` seam
(equal to `startDate + (d − 1)` in v1.3.0), so v1.4.0 changes the mapping
in one place. Choosing this alternative is an owner decision at any gate
from E1 onwards.

## Approval gates

| Gate | When | Owner decides |
|---|---|---|
| **A** | Phase 12A (done, PR #22 merged) | Arc-week model; metric naming; Weekly Focus and widget deferred |
| **A2** | after this PR's independent review | The sixteen decisions O1–O16 of [PHASE_12A_ADDENDUM.md § M](PHASE_12A_ADDENDUM.md#m-owner-decisions-gate-a2): above all the Freeze model and its next-day rule, the `ended` status, separate deletion, schema v7 and format 4, and this phase order. Merge the addendum |
| **E1** | end of 12E1 | migration and mapping results; continue as one release or stage it |
| **B** | end of 12B | summary copy sign-off; merge |
| **C** | end of 12C | "Missed" wording; merge |
| **D** | end of 12D | setup and confirmation wording; merge |
| **E2** | end of 12E2 | Freeze behaviour on the emulator; pause wording; merge |
| **F** | end of 12F | Restart and deletion wording; merge |
| **G** | end of 12G | the three sounds (listening), their names, default on; merge |
| **H** | end of 12H | integration verdict; go to release qualification |
| **I** | during 12I | authorization for the physical OnePlus signed upgrade; then independent review and merge |
| **P** | after 12I merge | separate publication authorization (tag, GitHub Release) |

No phase merges itself. Every PR waits for independent review and the
owner's merge. No phase begins before the gate in front of it.

## Release safety rules (all phases)

- **Identity:** package `com.nextrep.nextrep`; the permanent signing
  certificate (above); no key rotation; no new application id; no
  temporary suffix in source.
- **Data:** every Arc, habit, revision, progress row, XP entry, streak,
  achievement, reflection, reminder, Hydration and Focus Guard setting
  survives the upgrade. The v6 → v7 migration only adds: two empty tables
  and one nullable column. No existing row is rewritten. No destructive
  migration, no reset. v1.0.0 / v1.1.0 / v1.2.0 backups (formats 1–3)
  keep restoring.
- **Deletion:** only ever by the user's explicit, separately typed
  confirmation, only of the Arc named on screen. Never automatic, never
  as a side effect of Restart, never stored as a pending intent.
- **Rules:** no change to habit limits, goal-edit timing, Minimum Day,
  Perfect Day, XP amounts and keys, streak rules, levels or the 32
  achievements. A Rolling Arc is still 92 challenge days; a freeze moves
  dates, never day numbers already lived. Viewing a review or the
  calendar writes nothing. Freezing and resuming award nothing.
- **Privacy:** no new permission, dependency or network request; no
  analytics, telemetry, accounts or cloud. Sounds are bundled and local.
- **Distribution:** no automatic update installation. Signing only on the
  owner's machine. Physical device work only with explicit authorization.
  Publication only with separate authorization.
- **Process:** one PR per phase; CI green on the final head; independent
  review; owner merge.
