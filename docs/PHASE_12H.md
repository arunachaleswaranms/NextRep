# Phase 12H: Integration, Accessibility, Migration and Regression

## Objective and boundary

The v1.3.0 hardening phase ([V1_3_ROADMAP.md § 12H](V1_3_ROADMAP.md#12h-integration-accessibility-migration-and-regression)):
qualify the seven v1.3 features together, find and fix integration and
accessibility defects, verify migration and backup safety, keep v1.2.0's
behaviour, and hand Phase 12I a release-ready source tree.

No new feature. No schema change (v7), no backup-format change (writes 4,
reads 1–4), no new dependency, permission, network request, notification
channel, telemetry or analytics. Package `com.nextrep.nextrep`, version
`1.2.0+3`. No version bump, no production signing, no permanent key, no
signed v1.2.0 → v1.3.0 rehearsal, no physical device, no tag, no release:
all of those belong to Phase 12I and the publication gate.

## 1. Verified Phase 12G baseline

| | |
|---|---|
| PR #30 (Phase 12G) | **merged** 24 Nov 2026 11:56:45 UTC; final head `a1147a4032fd409e7b88ca812c38ea33430103f3`; squash merge `20712d21c1ec02bf3eba18222f3eeeafe7182a0d` |
| `origin/main` | `20712d21c1ec02bf3eba18222f3eeeafe7182a0d`, "Phase 12G: Completion Sounds (#30)" |
| Post-merge CI | run [45388828817](https://github.com/arunachaleswaranms/NextRep/actions/runs/45388828817) on `20712d2`: **success**, both jobs |
| Open PRs | none |
| Releases / tags | v1.2.0 is the latest published release; tags `v1.0.0`, `v1.1.0`, `v1.2.0` only. No release was created from 12G |
| Gate G | **approved by the owner on 24 November 2026** (from the owner's 12H brief): the six sounds after listening; Ice Crystal, Summit Spark, Warm Ember; sounds on by default with Ice Crystal; the remaining Gate G decisions; the documented device deferrals. Recorded in [PHASE_12G.md § Gate G outcome](PHASE_12G.md#gate-g-outcome) |
| Invariants (checked on `origin/main`) | package `com.nextrep.nextrep`; `version: 1.2.0+3`; `AppDatabase.schemaVersion` 7; `BackupFormat.formatVersion` 4, reader dispatch 1–4; `FocusGuardStore.SCHEMA_VERSION = 7L` (exact gate); release manifest's five `uses-permission` entries (seven merged permissions, the CI audit's set) |
| Dependencies | `pubspec.lock` SHA-1 `2cdc919a…e45` at the baseline; unchanged at the end of this phase |
| Worktrees | the primary checkout (on `phase/11b-smart-hydration`, clean) and all 13 phase worktrees were clean; none was touched |
| This phase | worktree `~/labs/NextRep-12H`, branch `phase/12h-v1.3-integration-hardening` from `20712d2` |

`PROJECT_STATE.md` still described Phase 12G as open (written before the
merge); it is corrected from the PR's merge record and the owner's brief.

## 2. Integration coverage matrix

Built from the specifications and the existing tests before any code was
written (a read-only inventory of the 167 test files). "Existing" means
tests already on `main`; 12H adds only what an integration reason needs.

| Requirement | Existing test / evidence | Gap | 12H action | Result |
|---|---|---|---|---|
| All seven features in one flow (roadmap § 12H, addendum § L6) | 12D setup flow (no logging), 12E2 pause flow, 12F restart flow, 12F service chain (no setup, no delete) | **No** single flow; no file-database process reconstruction across features | `phase12h_combined_flow_test` (3 scenarios, real file DB, reopened) | PASS |
| Same numbers on every screen (spec §§ 4.5, 12.5) | pure property tests (review ↔ ledger ↔ summary; calendar ↔ Journey); a few real-Drift checks | **Today** never compared; Insights vs summaries; resumed and scheduled-freeze Arcs on real Drift | `test/support/reconciliation.dart` checker; worked examples and 16 generated histories on real Drift | PASS |
| F1–F4 regressions (addendum § L7) | F1 and F2 fully tagged (12E2, 12F); F3 / F4 by meaning in 12B / 12E1 | none missing; F3-2 / F4 examples only on pure models | the spec's examples reproduced exactly on real Drift; every reconciliation asserts F3-1 / F4-11–14 | PASS |
| Migration v1 → v7 (brief § 6) | populated chains checked by app reads; row-by-row only from v4, v5, v6 | **full chain with every old row compared** | `migration_chain_test` (v1 active, v1 setup, v3 completed) | PASS |
| Direct v6 → v7 fixture | `migration_v7_test`: every v6 row, PRAGMA integrity and foreign keys, saved-setup and active variants | none | kept | PASS (existing) |
| Backup formats 1–4 | format 1 and 2 fixtures; format 3 only as a relabelled format-4 body; one format-4 lifecycle source | **no genuine format-3 file**; no complex round trip with a completed Arc, Hydration and every table compared | genuine v1.2.0 format-3 fixture; two complex format-4 round trips; formats 1–3 on a v1.3 device | PASS |
| Format 4 refused by v1.2.0 | relabel tests (`backup_v4_test`) | not run against the real v1.2.0 reader | v1.2.0's own code run on a 12H export | PASS |
| Layout and guidelines on every v1.3 surface (spec § 8.5) | sweeps of review, calendar, setup, pause, restart; sound settings at 6 layouts | ended Summary, Arc History with ended / paused Arcs, Today header, Habits with a scheduled pause, paused Journal, reorder menu, Sound & Feedback at 360 × 640 with reduced motion, two destructive dialogs | `phase12h_layout_test` | **2 defects** (D-1 below) → FIXED |
| Reduced motion (A5) | asserted on the review and calendar only | pause, resume, restart, delete, sound, hub, review, confirm | 11 screens in `phase12h_layout_test` | PASS; reorder list known limitation |
| Destructive consequences before confirmation (§§ 9.9, 9.11) | widget semantics present | order not asserted | `phase12h_destructive_semantics_test` | PASS |
| Midnight with a screen open | Today, review, calendar, Confirm & Start, pause / resume sheets, banner, restart, sounds | Delete Arc, Sound & Feedback, setup editor, hub, ended Summary, Arc History, paused calendar | `phase12h_midnight_test` (+ positive control) | PASS |
| TalkBack (A8, brief § 9) | never run in 12B–12G | all | emulator, explore by touch | see § 7 |
| Profile timings (spec § 10) | none | all | `integration_test/phase12h_performance_test.dart` | see § 11 |

## 3. Combined-flow results

`test/integration/phase12h_combined_flow_test.dart`: the app's services
and Drift transactions on a real SQLite **file**, a hand-moved clock, and
`AppDatabase` closed and reopened ("process reconstruction") at four
points. Nothing writes dates directly.

**Rolling flow** (with a completed 2026 Arc kept throughout):

1. Saved setup on 25 Feb 2027: a custom count habit, a template, an edited
   goal, a habit switched off; reordered. A new process: the setup is
   byte-identical, still `setup`, with no participation start.
2. Confirm & Start on 1 Mar: a start date the user wasn't shown is refused
   (every table identical); confirmed, Day 1 is 1 Mar; 25–28 Feb are no
   days of the Arc; Today follows the saved order.
3. Week 1: Perfect, partial, completed Minimum, missed (with a goal raised
   from Day 5), Minimum partial, Perfect (Reading switched off from Day 7),
   partial; a reflection. Week 1's review: 7 days, 2 Perfect, 2 Minimum
   chosen, 1 completed, 3 full.
4. Day 10: water logged, a goal edit for tomorrow, then Freeze: the pause
   starts tomorrow (F1-1), nothing else changes (Z4), today stays open
   (F4-6), no reminder is pending on a paused date (Z8).
5. Paused 11–19 Mar: four dates (one a Monday), each with the app's
   midnight work writing nothing; a new process on 14 Mar; Today not
   trackable; logging refused; the figures never move (F4-5); only Day 4 is
   missed (Z3).
6. Resume: the sheet shows 19 Mar, midnight passes, the shown date is
   refused (nothing stored), then accepted on 20 Mar: Day 11, end date
   31 May → 9 Jun, the waiting goal edit applies on the resume date (F1-2).
7. Days 11–14, then a pause exactly at the Week 2 / Week 3 boundary
   (Week 2 complete, Week 3 `paused`), resumed: two intervals, end date
   12 Jun; Week 1's review identical through both pauses (R10).
8. Day 21 after logging: Restart. Only the old session's status and
   `closed_on` change (T2); `closed_on` = today (F2-2); "Ended early · Day
   21 of 92"; the old ledger identical row for row; the new Arc on Day 1
   today with 0 XP, the same order and on / off state, the latest goals.
9. A new process; the ended Arc three days later has the same figures as
   on `closedOn` (F4-3); the date moved back before `closedOn` leaves its
   XP future-dated, then returns (F4-4, R19).
10. Deletion: an active Arc is refused; cancelling stores nothing; DELETE
    of the old Arc removes exactly its rows in every table; the completed
    and new Arcs remain.

**Seasonal late join:** joined on Day 20; Weeks 1–2 `beforeJoining`; Freeze
neither offered nor accepted (every table identical); Minimum and Perfect
Days; Restart with nothing logged today ends it on Day 30 (F2-1) and
starts a Rolling Arc (F2-9); 11 counted days, none before joining.

**Week 13:** a Rolling Arc lived to Day 86; a 400-day pause (figures fixed
at Day 86 on +1, +200 and +400; a new process); resumed as Day 87; Freeze
on Day 91 starts on the planned last date (F1-8); resumed as Day 92; Freeze
not offered on Day 92 (F1-9); Week 13 in progress with 7 settled days and
"Today so far"; completed the next day with an 8-day Week 13 and the final
wording; the clock moved back into the completed Arc gives one open day,
the status stays `completed` and nothing is written (F4-7, R22).

At **every** step every started Arc is reconciled on every screen (§ 4),
and the reconciliation writes nothing.

## 4. Cross-screen metric reconciliation

`test/support/reconciliation.dart` builds each screen's read model the way
its screen does (Today, Journey, Calendar, all 13 Weekly Reviews, Summary /
Arc History card, Insights) and checks them against figures it computes
**independently** from the stored session and raw `xp_transactions` rows
(SQL), by the spec's definitions — never from the app's own partition:

- `S(T)`, `O(T)`, `E(T)` disjoint and complete; `E(T)` = `elapsedDates`;
  no paused, pre-join or after-`closedOn` date in it;
- identities 1–3 of § 12.5.2 against `ArcSummary.daysElapsed`, `fullDays`,
  `consistencyPercent` and `perfectDays.total`; Minimum Days likewise;
- XP groups A–D of § 12.5.1 from the raw ledger: `A + B + C + D = total`,
  **`D = 0`**, `Σ X(w) = A`, "Today so far" = `B`, and the same total in
  `loadArc`, the Summary, Journey and the level;
- Calendar ↔ Journey: 92 cells in 13 blocks, the same state, date and
  "today" per day; full cells = `Σ F(w)`; one pause row per interval, after
  the right day, "scheduled" exactly until it begins; a paused date is never
  a cell and never `missed`;
- an open day exactly when `openToday`; on an ended Arc no today and the
  days after `closedOn` "Not reached";
- Today's date, trackability, completed count and Perfect flag equal the
  review's open day;
- Insights: Arc count, completed (an ended Arc never), elapsed, full,
  Perfect and Minimum Days and XP = the sum over Arcs;
- **every table identical before and after** (read-only).

`test/integration/phase12h_metric_reconciliation_test.dart`:

| Case | Figures (real Drift, the app's services) | Result |
|---|---|---|
| § 12.5.1 A / B | 195 XP; A 165 / B 30; rolled back: 105 / 60 / C 30 | exact |
| § 12.5.1 D, E, F | ended 12 Nov after logging, 2,430 XP: D and E 2,430 settled; F (11 Nov) 2,385 + C 45 | exact |
| § 12.5.1 H | the same Arc restored on a device on 10 Nov: 2,325 + C 105; the launch work adds no ledger row | exact |
| § 12.5.1 G / G′ | paused 11–19 Mar: 900; resumed: 1,005 + B 60 = 1,065 | exact |
| § 12.5.2 A | S 2, O 1, E 3, full 2, Perfect 2, 66% | exact |
| § 12.5.2 D′ / D | 9 + 1 / 10 + 0, full 6, Perfect 4, 60% | exact |
| § 12.5.2 E, F, G | 2 / 1 / 1, 50%; 50%; rolled back 1 / 0 / 0, 0%; back to E | exact |
| § 12.5.2 I, zero activity, first day | nothing divided; a quiet week counted, never full | exact |
| Generated histories | 16 seeds (Rolling and Seasonal), ~36 dates each, random logging, Minimum Days, goal edits, pauses, resumes, restarts, rollbacks of 1–3 days; every started Arc reconciled on every date; a tally proves pauses, resumes, Rolling and Seasonal restarts, rollbacks, active, ended and paused Arcs were all reached | PASS |

The cases the brief lists — zero activity, first day, Day 91 / 92, Week 13,
several and long freezes, today inside a week, a pause across a week
boundary, restart on a day with progress, an ended Arc on `closedOn` and
later, a rollback before `closedOn`, a Seasonal late join, restored paused
and ended Arcs — are each reached by § 3, this table or § 6.

No formula was changed. Two expectations in the new checker were wrong at
first and were corrected to the specification, not the code: an ended
Arc's days after `closedOn` keep their planned dates and show "Not reached"
(spec § 12.4), and `JourneyDay.isToday` marks the current date even on a
pre-join season day, whose state stays `notJoined` (its documented
contract).

## 5. Migration and backup matrix

### Migration (`test/data/migration_chain_test.dart`)

| Start | Data | Chain | Every pre-existing row and value | Only documented additions | New tables | PRAGMA | Reads |
|---|---|---|---|---|---|---|---|
| v1, active Arc | 8 habits (a custom one), 5 days of progress, the XP ledger | v1 → v2 → … → v7, validated against the v7 snapshot | **identical** (4 tables) | 3 Perfect Day bonuses (one per v1 Perfect date); `minimum_target` catalogue backfill; `arc_kind = rolling92`; `participation_start_date = start_date`; `closed_on` null | 9 empty; no `feedback_preferences` row → the approved defaults (on, Ice Crystal) | `user_version` 7; `integrity_check` ok; no foreign-key problem | reconciles; 3 Perfect Days; ledger + bonuses |
| v1, setup | 8 habits, never started | the same | identical | `participation_start_date` null | empty | the same | the setup and its order |
| v3, completed Arc | revisions, a Minimum Day, unlocks, Perfect bonus | v3 → … → v7 | identical (7 tables) | none | 6 empty | the same | reconciles; launch work re-derives nothing |
| v6 (existing) | saved setup or active Arc, completed Rolling and Seasonal, reminders, Focus Guard | v6 → v7 | identical (`migration_v7_test`) | `closed_on` null, empty `arc_freezes`, no feedback row | — | integrity and foreign keys | — |

No schema change; `schemaVersion` stays 7; Focus Guard's native gate stays
exactly 7 (JVM tests unchanged and passing). The signed v1.2.0 → v1.3.0
upgrade rehearsal is **not** part of 12H (Phase 12I).

### Backup (`test/integration/phase12h_backup_test.dart`)

| Format | Source | Result |
|---|---|---|
| 4, variant A | built only through the services: a completed Arc (revisions, Minimum Day, reflection, achievements), an Arc ended by Restart with two closed pauses and revisions, the restarted Arc paused again (open) after an earlier closed pause; daily, reflection and Hydration Coach reminders; Focus Guard with two apps; sounds off, Warm Ember | written as format 4; restored over a device holding other data and other sound settings: **every table equal to the source**, the only differences the documented ones (session ids shifted past ids the device used; child auto-increment ids; reminders, Hydration Coach and Focus Guard off; Focus Guard's apps and budget kept; settings' bookkeeping timestamps); sound settings as stored; nothing scheduled; every Arc reconciles with **the same figures as the source**; the launch work adds no XP, unlock, progress, session or freeze row; an export of the restored data restores to the same rows again |
| 4, variant B | the same history, the restarted Arc completed, then a reordered saved setup with a custom habit (the one open session) | the same; the setup is the open session, its order kept (hub) |
| 3 (**genuine**) | written by NextRep **v1.2.0's own services and exporter** (detached worktree at tag `v1.2.0`): a completed and an active Arc, a Minimum Day, a revision, a reflection, every reminder, Hydration Coach and Focus Guard on; committed as `test/fixtures/v1_2_0_backup_v3.nextrep` | restores on v1.3: no pause, no `closed_on`, no `ended`; **the device keeps its own sound setting**; nothing scheduled; no XP awarded; every Arc reconciles |
| 2 (genuine fixture) | v1.1 | the same |
| 1 (genuine fixture) | v1.0 era | the same (format-1 achievement backfill is existing, documented behaviour) |
| 4 read by v1.2.0 | a 12H export with an ended and a paused Arc, inspected by v1.2.0's own code | **refused**: `BackupFailure: Unsupported backup formatVersion 4`; v1.2.0's data unchanged |

Kept from earlier phases and passing: invalid backups and failures inside
the restore transaction change nothing (`backup_v4_test`,
`backup_restore_test`, `backup_v2_restore_test`, `phase11e_restore_test`);
format-4 states are never read from an older format; a restore plays no
sound (`sound_settings_test`, `completion_sound_stale_test`); a saved setup
restores to the hub (`setup_persistence_test`).

## 6. Accessibility and layout results

`test/integration/phase12h_layout_test.dart` (75 tests): 9 scenes × 7
layouts — 360 × 800 at 1× and 2×, 320 × 568 at 1.5×, 568 × 320, 800 × 360
at 1.3×, **1280 × 800**, 360 × 640 at 1.3× with reduced motion — each
scrolled through (no overflow, no clipped line, nothing sideways, buttons
and icon buttons ≥ 48 × 48 dp); Flutter's tap-target, labelled-target and
**text-contrast** guidelines on every scene at 1× and 2×; and reduced
motion on 11 v1.3 screens (nothing scheduled once shown).

| Finding | Evidence | Outcome |
|---|---|---|
| **D-1** Cancel Setup and Replace Data buttons: `textPrimary` on `danger` = **2.71 : 1** (reported in 12D, unfixed) | `textContrastGuideline` failed on the hub's Cancel Setup dialog | **FIXED AND RETESTED**: dark `background` text (6.68 : 1), the convention the 12F Delete Arc screen already uses; guideline passes on both dialogs at 1× and 2× |
| App-bar titles "Sound & Feedback", "Your habits", "Data & Backup" reported as ellipsized at 1×–2× | widget tests only (square test font) | **PASS on the device**: API 36 emulator at 360 dp and 2× text, each title in full (Material caps the title's text scale). Test-font artefact; app-bar titles left out of the clip check with this evidence |
| A 47.99999999999994 dp button height | floating-point rounding after a scroll | tolerance 1e-6 |
| Restart and Delete: every consequence before the field and the button; disabled buttons say why | `phase12h_destructive_semantics_test`, traversal order, 1× and 2× | PASS |
| Reorder list's built-in gap and settle animations under reduced motion (12D limitation 1) | `SliverReorderableList` hard-codes 250 ms | **DEFERRED** (owner decision H-3): replacing a framework widget is new UI; the drag is user-initiated and Move up / Move down (no animation) is the non-drag path |

## 7. TalkBack results (emulator)

Disposable AVD `NextRep12H_API36` (Pixel 7, API 36 `google_apis` arm64,
TalkBack 16.0.0.738667889), a debug build of this branch, synthetic data
pushed into the app's private storage; 360 dp (`wm density 480`) at 1×.

**Method and its limit.** `adb shell input` events bypass TalkBack's
touch explorer (an injected tap activates the control directly). Host
touches through the emulator's gRPC `sendTouch` **are** explored: a tap
moves TalkBack's focus without activating, and the focused node was read
by locating TalkBack's green focus frame in the framebuffer and matching
it to the uiautomator node. Swipe and keyboard navigation (and
double-tap) through gRPC were **not** recognised reliably (call latency
breaks gesture timing). So: **focus targets and their spoken labels were
verified by explore-by-touch; linear swipe order was not driven on the
device** — it is covered by the widget-level traversal tests (12B–12F and
12H).

| Surface | Explore-by-touch: focused node and label | Result |
|---|---|---|
| Today header (12G) | Share progress · Reminders · Sound & Feedback · "Achievements, 9 of 32 unlocked" · More options; "Day 12 of 92"; habit cards and Add / Complete buttons | PASS |
| Calendar | "Week 2 of 13, 8 to 14 April, 2 of 4 days full, this week. Opens the week review."; "Day 9, Friday 9 April. Partial, 75 percent complete." (spec § 8.1 form) | PASS |
| Weekly Review | header "Week 2 of 13. Days 8 to 14. Thursday 8 April to Wednesday 14 April. In progress." → summary → strip → stats ("Perfect Days: 2.", "Minimum Days: 0 completed, 0 chosen.") → "Today so far, Day 12: 0 of 4 habits, 0 XP. Today counts once it ends." → highlights → per habit | PASS |
| Sound & Feedback | switch with its description; "Ice Crystal" …; previews "Play Ice Crystal" …; the silence note | PASS |
| Pause sheet | every consequence, with full dates, before "Pause from tomorrow" and "Not now" | PASS |
| Scheduled banner | "Pause starts tomorrow. Today still counts." · "Cancel pause" | PASS |
| Paused Today | "Arc paused", Resume Arc, Journey, Journal, Arc History, Restart with this setup, Focus Guard | PASS |
| Resume sheet | "Today, Thursday 15 April 2027, becomes Day 13 of 92." · "Your new last day is Saturday 3 July 2027." · "You paused for 2 days." · Resume today · Not yet | PASS |
| Restart | intro, dates, "ends at Day 12 of 92", "It will not be marked as completed.", "starts with 0 XP…", "Your old Arc" group, then "Restart Arc. Type RESTART to enable." | PASS (and found D-2) |
| Delete Arc | the Arc, "Ended early · Day 13 of 92", "This permanently removes:", "13 challenge days and 735 XP", achievements, reflection, Journey, Insights, others kept, no undo, then the controls | PASS |
| Saved setup hub | "Your Arc Setup Is Saved", "Rolling 92-Day · 12 habits · 9 on", "Day 1 will be the day you start.", Start Challenge, Review Setup, Continue Editing, the settings links | PASS |
| Habit Setup (ordering) | "Push-ups, 20 reps, on, 1 of 12", handle "Reorder Push-ups", "Options for Push-ups" → Move up (disabled on the first) / Move down; Move down stored the new order | PASS |
| Review Setup | "1. Workout. 30 min. Minimum 10 min." … (one node each, new order) | PASS |
| Confirm & Start | heading, Arc, "Day 1: Today, Friday 16 April 2027", "Day 92: Friday 16 July 2027", the explanation, then the buttons; confirmed: Day 1 = 16 Apr (saved 10 Apr), order kept | PASS |
| Arc History | "Rolling Winter Arc, 1 Apr – 15 Apr 2027, ended early · day 13 of 92. Paused 2 days. Level 3, 735 XP …" | PASS |

**Completion sound with TalkBack on** (direct tap on No Junk Food):

| Question | Evidence | Result |
|---|---|---|
| The native player was asked to play | logcat `NextRepSound: play iceCrystal.habit: PLAYED` | PASS |
| The sound was emitted | gRPC `streamAudio` capture of the device output: a short −20.1 dBFS burst 0.7 s after the tap amid TalkBack speech (≈ −40 dBFS); **control** (reversing the completion, which plays nothing by rule): no play line, nothing above −38 dBFS | PASS on emulator output (not a phone speaker) |
| TalkBack speech continues without inappropriate interruption | TTS requests and speech-band energy continue after the sound; no audio focus is taken (12G); whether an in-flight utterance was shortened cannot be told from energy | **UNRESOLVED** (→ 12I physical device) |

**Not done:** physical-device TalkBack, Switch Access, hardware keyboard
navigation on a device, TalkBack swipe reading order on the device.

## 8. Midnight, lifecycle and timezone results

Widget tests (`phase12h_midnight_test`, with a positive control showing
the harness's day change reaches the app): midnight with Delete Arc, Sound
& Feedback, Habit Setup, the hub, an ended Summary, Arc History (ended and
paused Arcs) or a paused Journey calendar open — still usable, **every
table identical**, no sound. Earlier phases cover Today, the review, the
calendar, Confirm & Start, the Pause and Resume sheets, the scheduled
banner, Restart (and Day 92) and completed habits.

Integration tests: midnight during a scheduled Freeze and on paused dates
writes nothing; Resume on a different date than the sheet showed is
refused; Day 92 completion; Restart near a date boundary (12F); the clock
moved back before `closedOn` and into a completed Arc (§ 3).

### 8a. Emulator lifecycle run

The same disposable AVD and debug build, an Arc started through Confirm &
Start on 16 Apr 2027 (Day 1, a Perfect Day), daily, reflection and
Hydration Coach reminders turned on in the app. Pending reminders counted
per date from `dumpsys alarm`; every "nothing written" step is a full
`sqlite3 .dump` of the app database (root on the `google_apis` image)
compared before and after.

| Step | Observed | Result |
|---|---|---|
| Reminders on | pending: 16 Apr 1, 17–22 Apr 6 a day, 23–29 Apr 2 a day | — |
| Pause from tomorrow (Today ⋮ → Pause Arc) | `arc_freezes` 17 Apr, open; pending: only 16 Apr's evening reflection; **none on a paused date** (Z8) | PASS |
| Midnight with Today open (23:59:40 → 00:00:27) | Today changed to "Arc paused" by itself; database **identical**; nothing pending | PASS |
| Home and back; force-stop and relaunch | still "Arc paused"; database identical | PASS |
| Time zone IST → Los Angeles (local date back to 16 Apr) and back | 16 Apr: "Day 1 of 92", "Pause starts tomorrow. Today still counts."; back: "Arc paused"; database identical throughout | PASS |
| `adb reboot` while paused, clock set to 20 Apr before the first launch | nothing pending after boot; "Paused since Saturday 17 April 2027, 3 days" | PASS |
| Resume on 20 Apr (not the day it was planned) | sheet: "becomes Day 2 of 92", "new last day is Monday 19 July 2027", "You paused for 3 days"; stored: end date 19 Jul, pause 17 → 20 Apr; reminders re-planned from 20 Apr | PASS |
| Restart on a resume day, Delete Arc | see § 7 and D-2 | FIXED AND RETESTED |

Not re-run on the device in 12H: Focus Guard's background check across
these steps (unchanged code; 12E2's device run covered pause, resume,
kill and reboot with Focus Guard on), a clock rollback before a resume
date (widget and Drift tests), Day 92 completion (Drift tests).

## 9. Sound integration results

All 12G behaviour kept; sounds, generator, names, default and player
unchanged (asset SHA-256s and `--check` unchanged).

- Plays only on a saved incomplete → complete transition: on the device a
  tap loop that alternately hit a snackbar's Undo and re-completed a habit
  logged 83 plays for 83 saved re-completions (an automation artefact,
  reproduced deliberately: Undo → stored 25/0, no play; re-complete →
  30/1, one play; four increments short of the goal → no play).
- No sound at restore, launch, screen opening, refresh, midnight or
  backfill (`phase12h_midnight_test`, the backup tests, 12G's tests);
  restore over completed habits plays nothing (12G).
- No extra XP or achievement from playback; native errors never affect
  persistence (`completion_sound_regression_test`, unchanged).
- G-R1 cancellation (navigation, background, Arc changes) unchanged and
  its 18 widget tests pass. The known residual (a page pushed outside the
  router stays eligible for ~300 ms of its transition) was **not re-tested
  on the device** in 12H; no reproducible defect appeared in the 12H
  device runs, so it stays documented as in 12G, unchanged.
- No audio focus, ducking or permission (`completion_sound_boundary_test`).

## 10. Full v1.2 regression results

See § 17 (local validation) for the counts. The whole suite ran
unchanged except one historical expectation, changed **with** defect D-2:
`arc_restart_rules_test` "never a paused date" now expects the resume date
`d(8)` instead of `d(3)` for a restart on the resume date (the old value
was the one the transaction refused); the test's intent — never a paused
date — holds.

## 11. Performance measurements

**Informational, not a gate** (spec § 10). `integration_test/phase12h_performance_test.dart`
run with `flutter drive --profile` on the disposable AVD (Pixel 7 profile,
API 36 `google_apis` arm64, software GPU `swiftshader_indirect`, on an
Apple-silicon Mac). History built in-process: a completed Arc, an Arc
ended by Restart with a pause, and an active Arc on Day 86 with its own
pause (later paused again for the "paused" case). Each value is the time
from the action to the first settled frame (`pumpAndSettle`), 5
iterations, after a warm-up; a route open **re-mounts the whole app**
(a cold mount of the app at that route, not a navigation). Run twice:
animations on, and reduced motion (every transition instant, so the time
is the work).

| Operation | Animations on, median (min–max) ms | Reduced motion, median (min–max) ms |
|---|---|---|
| Open Today (Day 86, populated) | 812 (784–832) | 831 (816–836) |
| Weekly Review, Week 1 | 711 (680–719) | 716 (683–717) |
| Weekly Review, Week 7 | 699 (683–715) | 715 (698–720) |
| Weekly Review, Week 13 | 716 (699–716) | 700 (683–718) |
| Journey Path → 92-day Calendar (in place) | 699 (692–700) | **230 (218–233)** |
| Arc History, 3 Arcs | 816 (801–833) | 832 (814–834) |
| An ended Arc's summary | 2,436 (2,400–2,479) | **701 (698–715)** |
| Sound & Feedback | 700 (699–700) | 701 (698–716) |
| Tab to Journey / Journal / History / Today (in place) | 684 / 699 / 698 / 687 | **119 / 117 / 117 / 116** |
| A paused Arc's Today (animations on) | 699 (698–717) | — |
| Inspect + restore the complex backup (service, no UI) | 13 (10–34) | — |

Reading: in-place changes (tabs, Path → Calendar) cost about 115–230 ms
of work; the rest of the ~700 ms is the app's 600 ms entry motion. Route
opens sit near 700 ms in both modes because each re-mounts the app. The
ended summary's extra ~1.7 s is its entry animation (gone with reduced
motion). Weeks 1, 7 and 13 cost the same. **No severe regression; nothing
is gated.** These are emulator figures, not a phone (U-8).

## 12. Defects discovered and corrected

| # | Defect | Severity | Fix | Regression tests | Status |
|---|---|---|---|---|---|
| D-1 | Cancel Setup (hub, editor) and Replace Data (restore) danger buttons: light text on `danger`, 2.71 : 1 | accessibility (text contrast, WCAG 1.4.3) | dark text (`background`), 6.68 : 1, as on the Delete Arc screen | `phase12h_layout_test` contrast guideline on both dialogs, 1× and 2× (failed before the fix) | **FIXED AND RETESTED** |
| D-2 | Restart offered on the date an Arc was resumed, before anything was logged that day, then refused by its transaction ("Couldn't restart. Nothing was changed."): the last lived day fell before the pause just closed, and an ended Arc may not hold a pause after `closed_on` | functional (restart blocked on every resume day until something is logged) | the resume date counts as lived on its own date, like Day 1 — the same `closed_on` a restart the next morning gives; the pause is kept; no stored row changes | `phase12h_restart_resume_day_test`: the device case (every row as specified, backup round trip, reconciliation), unchanged neighbours, and a 54-case grid "whenever Restart is offered, the transaction accepts it" (2 of 3 tests failed before the fix with the device's error) | **FIXED AND RETESTED** (unit, Drift, emulator); owner decision H-1 |

## 13. Known unresolved limitations

| # | Limitation | Classification | Owner / phase |
|---|---|---|---|
| U-1 | TalkBack speech continuity while a completion sound plays: emitted together on the emulator; whether an utterance is shortened can't be told from the output energy | **DEFERRED WITH REASON** (needs a person listening on a phone) | 12I physical OnePlus, if authorised |
| U-2 | TalkBack linear (swipe) reading order and double-tap activation on a device: the emulator's injected gestures were not recognised; focus targets and labels verified by explore-by-touch, order by widget tests | **DEFERRED WITH REASON** (tooling) | 12I physical device |
| U-3 | Reorder list's built-in 250 ms gap / settle animations under reduced motion (12D) | **DEFERRED WITH REASON**: owner decision H-3 | v1.4 if a custom list is wanted |
| U-4 | Headphones / Bluetooth, OxygenOS sound behaviour, the 1 s "never late" rule on a slow phone, real-speaker loudness (12G) | **DEFERRED** (no device in 12H) | 12I |
| U-5 | iOS sound playback and silent switch (12G); iOS VoiceOver | **DEFERRED** (no iOS release planned) | — |
| U-6 | G-R1 residual (non-router page transition, ≤ ~300 ms) | accepted in 12G; unchanged | — |
| U-7 | 12E2 R1 residual (a clock set back to later on the scheduling day can't be detected offline) | accepted in 12E2; unchanged | — |
| U-8 | Profile timings come from an emulator, not a phone | informational by design | 12I may re-measure on the OnePlus |

No **BLOCKER** is open.

## 14. Copy and tone decisions

Every new v1.3 string was read in context (screens, sheets, empty,
error and historical states, screen-reader labels). Terminology is
consistent: the spec's "Freeze" / "Frozen" appear nowhere in the UI, which
says **Pause** / **Arc paused** / **Resume** throughout (Gate E2's approved
wording); "Ended early · Day N of 92", "Restart with this setup", "Delete
Arc", "Sound & Feedback", "Confirm & Start", "Perfect Day", "Minimum Day"
and "challenge days" are used the same way everywhere they appear;
singular / plural forms are handled ("1 day" / "6 days", "1 Journal
reflection"); XP uses grouping separators ("2,430 XP"); paused-date ranges
follow the approved forms. **No approved wording was changed in 12H.**

**Gate H copy and tone decision table** (proposals only; nothing below is
implemented unless the owner chooses it):

| # | Where | Today | Proposal | Rationale | Recommendation |
|---|---|---|---|---|---|
| C-1 | Saved-setup hub, bottom button | "Cancel setup" | "Cancel Setup" | its siblings (Start Challenge, Review Setup, Continue Editing) and the dialog's own button ("Cancel Setup") are Title Case | change (copy only) |
| C-2 | Restart intro | "…on Day 1 with your 7 habits, goals and order." (counts habits that are switched off; Today showed 4) | "…with your 7 habits (4 on), goals and order." | matches the hub's "12 habits · 9 on"; avoids reading as 7 active habits | change, or keep |
| C-3 | Arc History card, screen-reader label | "…, ended early · day 13 of 92. Paused 2 days. …" (lower case mid-sentence) | keep | read as one sentence; the visible card says "Ended early · Day 13 of 92" | keep |
| C-4 | Today habit card, screen-reader label | starts with the progress value ("0, Workout, 0, 30 min, …", Flutter's merged progress indicator) | out of 12H scope (v1.0 behaviour, not a v1.3 string) | noted for a later accessibility pass | defer |
| C-5 | Weekly Review per-habit counts | "1 of 1 days" possible in a one-day week | keep (Gate B approved; idiomatic) | — | keep |

**Gate H decisions** (behaviour and visuals):

| # | Decision | Recommendation |
|---|---|---|
| H-1 | Accept D-2's rule clarification: a restart on the date an Arc was resumed (with nothing logged yet) ends it on that date, like Day 1. Alternatives: keep refusing on the resume date (Restart offered then failing — not recommended), or end it before the pause and delete the pause row (rewrites history — not recommended) | accept |
| H-2 | Accept D-1's visual change: dark text on the red Cancel Setup and Replace Data buttons (as Delete Arc) | accept |
| H-3 | The reorder list's short drag animations under reduced motion: keep (user-started drag; Move up / Move down is the non-drag path) or ask for a custom reorderable list in a later release | keep for v1.3 |
| H-4 | CI: the "Format, analyze and test" job's timeout raised from 20 to 30 minutes (it took 19 minutes at 12G; 12H adds its suites). No step removed or weakened | accept |
| H-5 | The copy proposals C-1 and C-2 | owner's choice |
| H-6 | The unresolved device items U-1, U-2, U-4 assigned to 12I | accept |

## 15. Gate H checklist

- [x] Baseline verified (PR #30 merged, CI 45388828817 green, no open PR,
      v1.2.0 latest, invariants)
- [x] PROJECT_STATE corrected; Gate G recorded
- [x] Combined flow, Rolling + Seasonal + Week 13, real Drift, process
      reconstruction
- [x] Cross-screen reconciliation (worked examples exact; generated
      histories)
- [x] Migration chain v1 → v7 and v3 → v7, every old row compared;
      v6 → v7 kept
- [x] Backups 1–4 (genuine 1, 2, 3), complex format-4 round trips, v1.2.0
      refusing format 4
- [x] Layout, guidelines, reduced motion, destructive announcements,
      midnight
- [x] TalkBack on the emulator (explore-by-touch), with U-1 / U-2 open
- [x] Emulator lifecycle: midnight, background, kill, zone change, reboot,
      resume on another date, reminders
- [x] Performance recorded (informational)
- [x] D-1, D-2 fixed with regression tests (mutation-checked)
- [x] Full suite, JVM tests, builds, audits (§§ 17–18)
- [ ] Independent technical review of the PR
- [ ] Owner decisions H-1 … H-6 and the copy table
- [ ] Owner Gate H sign-off
- [ ] Owner's merge decision

## 16. Phase 12I handoff requirements

1. Version bump to `1.3.0+4` (only in 12I), release notes
   `docs/releases/v1.3.0.md` (state that a v1.3 backup can't be restored
   into v1.2.0, which refuses format 4 without changing anything — shown
   in § 5).
2. Signed candidate with the permanent key in the main checkout only;
   permission audit (the same 7 permissions and merged components as
   v1.2.0); two clean builds byte-identical.
3. Signed v1.2.0 → v1.3.0 `adb install -r` rehearsal on a **disposable**
   AVD with synthetic data: a real v6 → v7 migration, every v6 row
   compared, a format-3 backup before and restored after, Focus Guard's
   natural run after the upgrade.
4. Physical OnePlus, only after the owner's explicit authorisation:
   backup first, in-place signed upgrade, data compared, smoke of every
   v1.3 feature, sounds on silent / vibrate / DND / ringer, TalkBack
   reading order and speech with a completion sound (U-1, U-2),
   headphones, the 1 s "never late" latency (U-4), and, if wanted, profile
   timings on the phone (U-8).
5. Recheck D-1 and D-2 on the signed candidate (Cancel Setup / Replace
   Data text; a restart on a resume day).
6. Keep: package, signer, schema v7, format 4, no new permission or
   dependency, no network but the manual update check.

## Pre-PR independent review

An independent code review of the branch before the PR found no blocker
and confirmed D-2's rule (including several pauses, a rollback after a
resume, Day 92, a resume on the first paused date, and that the preview
and the transaction call the same function). Acted on:

- **Spec aligned:** [ARC_CONTROL_SPEC.md § 6.2](ARC_CONTROL_SPEC.md#62-what-happens-in-one-transaction)
  and addendum AD11 now list the resume date as lived, marked as the 12H
  correction pending owner decision H-1.
- **Backup test strengthened:** the restore rule "every reminder and
  Hydration Coach off" is asserted on the restored rows directly (the
  table comparison normalised it on both sides); the other reminder
  settings are asserted kept.
- Nits: a tautological ledger assertion removed from the reconciliation
  checker; two comments corrected. The checker's Calendar ↔ Journey
  comparison is weak by construction (the calendar is built from the
  Journey); the independent figures (`S`, `O`, `E`, groups A–D) carry the
  weight.

## 17. Local validation

All run in `~/labs/NextRep-12H` (Flutter 3.47.5, Dart 3.13.4, JDK 21 for
Gradle). The worktree has no `android/key.properties`: the release APK is
signed with the debug key (a compile and audit artifact only).

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 420 files, 0 changed |
| `flutter analyze` | no issues |
| `flutter test` (baseline `20712d2`) | **2,311 passed**, 0 failed, 0 skipped |
| `flutter test` (this branch) | **2,436 passed**, 0 failed, 0 skipped = 2,311 + **125 new** |
| New 12H tests by file | layout 75; metric reconciliation 24; midnight 8; backup 5; destructive semantics 4; combined flow 3; migration chain 3; restart on a resume day 3 |
| Historical tests changed | one expectation in `arc_restart_rules_test` with defect D-2 (§ 10); none weakened |
| Native JVM (`:app:testDebugUnitTest`) | **87 passed**, 0 failed (unchanged) |
| Mutation check of the new suites | 7 of 7 deliberate defects detected (paused dates participating; Minimum Days dropped from full days; restore losing `closed_on`; v4 → v5 marking setups started; a misplaced calendar pause row; an ended Arc keeping an open day; Insights counting an ended Arc as completed); D-2's tests fail on the unfixed rule |
| `flutter build apk --debug` / `--release` | both built |
| `dart run tool/sounds/generate_completion_sounds.dart --check` | 6 files, 125,064 bytes, reproduce |
| `flutter drive --profile` performance run | passed (§ 11) |
| iOS: `flutter build ios --simulator --debug`; `integration_test/phase11e_ios_smoke_test.dart` on the iPhone 17 simulator (iOS 27) | simulator build succeeded; smoke **passed** (1 / 1) |

## 18. Permission, dependency and network audit

- **Permissions:** CI's own release audit script, replayed locally on the
  release APK: exactly the 7 expected permissions (`INTERNET`,
  `RECEIVE_BOOT_COMPLETED`, `PACKAGE_USAGE_STATS`, `WAKE_LOCK`, `VIBRATE`,
  `POST_NOTIFICATIONS`, the app-private receiver permission); no forbidden
  permission, service, foreground service or WebView; Focus Guard's
  provider present and not exported; R8 keeps WorkManager's and Focus
  Guard's constructors; the six sounds stored uncompressed.
- **Identity:** `com.nextrep.nextrep`, versionName 1.2.0, versionCode 3;
  `AndroidManifest.xml` byte-identical to `main`.
- **Dependencies:** `pubspec.yaml` and `pubspec.lock` byte-identical to
  `main` (SHA-1 `6738cb76…`, `2cdc919a…`); nothing under `android/`,
  `ios/` or `assets/` changed.
- **Network:** no new network code; `test/app/network_boundary_test.dart`
  and `completion_sound_boundary_test.dart` unchanged and passing; the new
  tests use no network.
- **Code changes in `lib/`:** two files for D-1 (button colours), one for
  D-2 (`ArcRestartRules.lastLivedDay`). No schema, format, validator,
  migration or native change.

## 19. CI

`.github/workflows/flutter-ci.yml` gains one named step, "Phase 12H
tests", running the eight new files; the full suite still runs in "All
tests". The "Format, analyze and test" job's timeout goes from 20 to 30
minutes (it used 19 minutes at 12G; owner decision H-4). Nothing else
changes. The exact-head CI run is recorded in the PR.

`integration_test/phase12h_performance_test.dart` and the new
`test_driver/integration_test.dart` are for on-device runs only (CI never
runs `integration_test/`).

## Evidence location

Device evidence (logcat excerpts, audio envelopes, focus surveys, database
diffs) was gathered on the disposable AVD `NextRep12H_API36`, deleted
after the phase; the figures above are copied from it. No real user data,
no official install, no physical device and no signing key were used.
