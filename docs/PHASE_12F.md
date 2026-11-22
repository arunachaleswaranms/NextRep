# Phase 12F: Restart and Optional Arc Deletion

## Objective and boundary

The fifth v1.3.0 user-facing feature: a user can begin a fresh Rolling
92-Day Arc on Day 1 today with their existing habits, while the current
Arc is kept as **Ended early** by default; and, only through a separate
typed-DELETE screen, permanently delete a finished Arc. Built on the
approved [ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md) §§ 3, 6, 7, 9.9–9.11
and 10 (T1–T11), [PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md) AD10–AD13,
AD19, § L4 and § L7 (F2), and
[ARC_MOMENTUM_SPEC.md § 12](ARC_MOMENTUM_SPEC.md#12-lifecycle-addendum-freeze-and-restart),
on the schema-v7 foundation of [PHASE_12E1.md](PHASE_12E1.md) and the
freeze model of [PHASE_12E2.md](PHASE_12E2.md).

No schema, migration, backup format, validation, dependency, permission,
network, analytics, notification channel, reminder type, version or
application-id change. No XP, streak, Perfect Day, Minimum Day, revision
or achievement rule change. No sounds (12G) and no 12H hardening. Focus
Guard's native code and worker are unchanged. Version `1.2.0+3`; no
release; no physical phone; no production signing.

## Verified baseline

| | |
|---|---|
| PR #28 (Phase 12E2) | **merged** 22 Nov 2026 17:01 UTC; final head `bc1102245e2ec82d57a189560be763521ea6a55c`; merge commit `b751dff` |
| `origin/main` | `b751dff711f5fbd05ec583541a6b96b0d7d7b37f`, "Phase 12E2: Freeze and Resume (#28)"; nothing landed after it |
| Post-merge CI | run [45047072621](https://github.com/arunachaleswaranms/NextRep/actions/runs/45047072621) on `b751dff`: **success**, both jobs ("Format, analyze and test"; "Android builds and permission audit") |
| Open PRs | none |
| Release | v1.2.0 is the latest published release (v1.1.0, v1.0.0 before it) |
| Invariants | package `com.nextrep.nextrep`; version `1.2.0+3`; `AppDatabase.schemaVersion` 7; backup writes format 4, `readableVersions {1, 2, 3, 4}` |
| Worktrees | the primary checkout and the 11 phase worktrees (11C–12E2) were clean and were not touched |
| Worktree | `~/labs/NextRep-12F`, new branch `phase/12f-v1.3-restart-delete` from `b751dff` |

`PROJECT_STATE.md` still described PR #28 as awaiting the owner's merge;
it is corrected here from the PR's merge record.

## Architecture

```
Habits "Restart with this setup" ─┐
Paused Today "Restart with this setup ›" ─┴─► /restart?arc=<id>  RestartScreen
   (Seasonal: "Start a Rolling Arc with this setup")       │ preview: ArcRestartService.preview (read-only)
                                                           ▼ typed RESTART, Keep (default) | Delete it…
runRestart ──► ArcRestartService.restart (SerialQueue, one clock read)
                   │
                   ▼
   WinterArcRepository.restart ── ONE Drift transaction:
      read: session + freezes, the unfinished arc's id, habits + revisions,
            lastActivityDate (never revisions)
      ArcRestartRules.decide (pure)  → RestartPlan, or throw: nothing written
      write: delete the open freeze (if any); old session status=ended,
             closed_on (WHERE status='active'); insert new active Rolling
             session; insert its habits
      read back: both sessions == plan, problemWith == null, exactly one
                 unfinished arc (the new one), new habits == plan
                 → otherwise throw: everything rolls back
   ▼ committed
celebrations cleared → ReminderService.reconcile → arcRefresh + arcsChanged
→ arcResolution.reconcile (router) ──► Keep: success screen (§ 9.10)
                                     └► Delete it…: /arc/<old>/delete?after=restart

DeleteArcScreen (typed DELETE; also from any finished arc's Summary)
   ──► ArcRemoval.deleteFinishedArc ──► WinterArcService.deleteFinishedArc
        ──► WinterArcRepository.deleteSession(id, expected: its status)
            ONE transaction: status re-checked; cascade; orphan check
```

| File | Role |
|---|---|
| `lib/domain/winter_arc/arc_restart.dart` | **New.** `RestartBlocker`; the pure `ArcRestartRules` (`blockerOn`, `lastLivedDay`, `baselineFrom`, `decide`); `RestartPlan`, `RestartFacts`, `RestartOutcome`, `RestartPreview` |
| `lib/domain/winter_arc/arc_restart_service.dart` | **New.** `ArcRestartService`: `preview` (read-only) and `restart` (serialised, one transaction, one clock read) |
| `lib/domain/winter_arc/winter_arc_repository.dart`, `lib/data/drift_winter_arc_repository.dart` | `restart`: the transaction above. `deleteSession` refuses an `active` arc whatever was asked |
| `lib/domain/winter_arc/winter_arc_service.dart` | `deleteFinishedArc` (completed **or** ended; the status read is required again inside the deletion's transaction). `deleteCompletedArc` kept as its alias for existing callers |
| `lib/domain/habit/habit_config.dart` | `HabitHistory.latestConfig`: a habit's last revision whatever its date, else its baseline |
| `lib/core/errors/app_failure.dart`, `lib/shared/formatting/failure_messages.dart` | Rules `restartUnavailable`, `restartDateChanged`; `arcNotDeletable` wording covers finished arcs |
| `lib/app/dependencies.dart`, `lib/app/router/app_router.dart` | `arcRestartServiceProvider`; routes `/restart?arc=<id>` (needs an active arc, else the redirect sends the app home, e.g. to a just-completed arc's summary) and `/arc/:id/delete[?after=restart]` (the active arc's id redirects to Today) |
| `lib/features/arc_restart/` | **New.** `restart_labels.dart` (all wording), `restart_actions.dart` (`runRestart`, `restartEntryProvider`), `restart_screen.dart` (§ 9.9 + § 9.10), `delete_arc_screen.dart` (§ 9.11), `typed_word_field.dart` (`TypedWordField`, `ScreenHeading`) |
| `lib/features/habits/habits_screen.dart`, `lib/features/arc_pause/paused_arc_card.dart`, `lib/features/today/today_screen.dart` | Entry points |
| `lib/features/summary/*`, `lib/features/history/widgets/arc_history_tile.dart`, `lib/shared/formatting/arc_labels.dart` | "Ended early · Day N of 92"; Delete Arc for any finished arc opens the typed screen (the old dialog is removed, owner decision O11) |
| `.github/workflows/flutter-ci.yml` | A named Phase 12F test step |

There is **no second lifecycle or date-mapping engine**: every date
question goes through 12E1's `WinterArcSession` mapping
(`isParticipatingOn`, `participatingDatesThrough`, `dayNumberOf`,
`isFrozenOn`, `isOverOn`), the clock guard is 12E1's `ArcClockGuard`, the
last activity date is 12E2's `queryLastActivityDate` (never revisions),
and the new arc's dates come from `WinterArcRules.endDateFor`.

## Transaction and rollback

| Step (inside `_db.transaction`) | On failure |
|---|---|
| Read the session by id (with freezes), the unfinished arc's id, the habit history, `lastActivityDate` | `sessionNotFound` / storage error: nothing written |
| `ArcRestartRules.decide` (see below) | a `DomainFailure`: nothing written |
| Delete the open freeze `(session, frozen_from, resumed_on IS NULL)`, expecting one row | rollback |
| `UPDATE winter_arc_sessions SET status='ended', closed_on=… WHERE id=? AND status='active'`, expecting one row | rollback |
| Insert the new session (`rolling92`, `active`, start = participation = today, end = today + 91, `created_at` = `started_at` = now) | rollback (the `single_open_session` index also refuses a second unfinished arc) |
| Insert its habits in one batch | rollback |
| Read back and compare with the plan; `problemWith` on both; exactly one unfinished arc and it is the new one | `invalidArc`: rollback |

`decide` refuses, in this order: a date not shown (`restartDateChanged`);
a completed arc, or an active arc that is over today (`arcCompleted`: it
completes at the next refresh instead, never "ended" on Day 93); not the
active, unfinished arc (`restartUnavailable`: a setup, an ended arc, a
stale id, a second tap after the commit); the clock guard
(`clockBehindHistory`: today before the participation start, the latest
activity or the latest resume); a last lived day other than the one shown
(`restartDateChanged`: e.g. a habit logged after the screen opened); stored
activity after the last lived day (`invalidArc`: only damaged data);
every habit off at its latest configuration (`noHabitsSelected`, the
existing start rule).

What is written, and nothing else:

- **Old arc:** `status = ended`, `closed_on`, and the deletion of a
  scheduled or in-effect (open) freeze. Its planned `end_date`, closed
  freezes, habits, goal revisions (including one waiting for tomorrow),
  progress, day modes, XP, unlocks and reflections are untouched.
- **New arc:** one `winter_arc_sessions` row and its `habits` rows. No
  revision, progress, mode, XP, unlock, reflection or freeze.
- **App-level:** nothing. Reminder, Hydration Coach, Focus Guard and sound
  settings are not part of an Arc.

After the commit, best effort and repeatable (each is what a launch does
anyway): queued celebrations are cleared, reminders are re-planned for
the new arc, every arc-dependent provider re-reads, and the arc
resolution (which drives the router) is reconciled; if that re-read fails
the app reloads from storage as at launch (the `ArcRemoval._next`
pattern). A process death at any point after the commit is recovered by
the next launch: nothing replays and no intent is stored.

Deletion is a **separate, later** transaction (D3): the existing
`deleteSession` cascade with its orphan check over every arc-owned table
(including `arc_freezes`), by the old arc's id and only while its status
is still the finished status that was read. An `active` arc is refused by
the service and by the repository.

## The last lived day (`closed_on`)

`ArcRestartRules.lastLivedDay` (spec § 6.2, addendum AD11): the first of

1. today, when today is a challenge date and `lastActivityDate == today`;
2. the last challenge date before today
   (`participatingDatesThrough(today − 1).last`: paused dates are skipped,
   an open pause ends the list);
3. the participation start (a Day-1 restart with nothing logged).

A goal revision is configuration and never in `lastActivityDate`, so a
date with only a waiting revision is never lived. The result is always a
challenge date, never paused, never after today. With the clock behind
the history the restart is refused instead (AD19).

| Case (tested) | `closed_on` |
|---|---|
| Day 10, two habits logged, goal edited today (§ 6.7 row 1, F2-2) | Day 10; the revision dated Day 11 stays, unapplied |
| Day 10, nothing logged, goal edited (§ 6.7 row 2, F2-1) | Day 9 |
| Activity dated 18 Oct, clock 17 Oct (§ 6.7 row 3, F2-4) | refused, naming 18 Oct; on 18 Oct → 18 Oct (F2-5) |
| Paused since 20 Oct, restarted 25 Oct (§ 6.7 row 4, F2-7) | 19 Oct (Day 13); the open pause removed |
| Day 1, nothing logged (§ 6.7 row 5, F2-10) | Day 1, one counted day |
| Freeze scheduled for tomorrow (F2-6) | today with activity, else yesterday; the scheduled pause removed |
| Paused after earlier closed pauses (F2-7) | the last challenge day before the open pause; closed pauses kept |
| Day 91, Day 92 (F2-8) | that day with activity, else the day before; `ended`, never completed, no Summit, also on every later date |
| Active Seasonal, late join (F2-9) | the season day (Day 44); season dates unchanged; new arc Rolling from today |
| A reflection or a Minimum Day alone | counts as activity |

## The new arc's habits

`ArcRestartRules.baselineFrom`: each habit of the old arc, in display
order, with its **latest** configuration (`HabitHistory.latestConfig`: the
last revision whatever its date, so an edit saved today for tomorrow is
included). Copied: id (built-in or `custom_…`), title, type, unit, icon,
`sort_order`, target, Minimum Day target, on/off. Not copied: any
revision, progress, mode, XP, unlock, reflection or freeze. An all-off
latest configuration is refused by the existing start rule.

## Screens and wording

All new copy lives in `lib/features/arc_restart/restart_labels.dart`.

| Surface | Wording |
|---|---|
| Entries | Habits: "Restart with this setup" (Seasonal: "Start a Rolling Arc with this setup"); paused Today: "Restart with this setup ›". Shown for the active arc only (running, scheduled to pause, paused); never for a completed or ended arc, nor one over and about to complete |
| Restart (§ 9.9) | heading = the entry's words; "A new Rolling 92-Day Arc starts today on Day 1 with your 7 habits, goals and order." · "Day 1: today, Fri 16 Oct · Day 92: Fri 15 Jan 2027" · "Your current Arc ends at Day 10 of 92." · "It will not be marked as completed." · "The new Arc starts with 0 XP and its own streaks and achievements." · Day 92: "Today is this Arc's last day. If you wait until tomorrow it will be completed." · YOUR OLD ARC: "Keep my old Arc in Arc History" (selected) / "Delete my old Arc…" "Asks again, separately, after the restart." · "Type RESTART to confirm" · "Restart Arc" · "Cancel" |
| Seasonal | "You will leave the Seasonal Winter Arc on Day 44. A new Rolling 92-Day Arc starts today on Day 1." · "It uses your 7 habits, goals and order." · button "Start Rolling Arc" |
| Pause notes | scheduled: "The pause you scheduled is cancelled. Nothing was paused."; paused: "Your pause ends here. Paused days are never counted." |
| Refusals / errors | "Your phone's date (17 Oct) is earlier than your latest logged day (18 Oct). You can restart from 18 Oct. Nothing was changed." (also "the day your Arc last resumed", "your Arc's first day"); "Couldn't restart. Nothing was changed." + Retry; "The date changed while this was open. These are the new details."; "This Arc can't be restarted now. Nothing was changed." |
| Success (§ 9.10) | "Your new Arc has started" · "Day 1 of 92 · Fri 16 Oct 2026" · "Your previous Arc is in Arc History:" · "Ended early · Day 4 of 92 · 60 XP" (emulator) · "Go to Today" · "View previous Arc ›" |
| Delete (§ 9.11) | after a restart "Delete your previous Arc?" + "Your new Arc has started and is safe. This step is separate and optional."; from a summary "Delete this Arc?"; "Rolling 92-Day · 13 Nov – 13 Nov 2026" · "Ended early · Day 1 of 92" (or "Completed") · "This permanently removes:" • "1 day of progress and 15 XP" • "1 achievement" • "0 Journal reflections" (emulator) • "its Journey, weekly reviews and goals" · "Insights will no longer include it." · "Other Arcs and your settings are kept." · "This cannot be undone without a backup." · "Export a backup first" · "Type DELETE to confirm" · "Delete previous Arc" / "Delete this Arc" · "Keep it"; "Couldn't delete. Nothing was removed." + Retry; snack "Winter Arc deleted." |
| History / Summary | Arc History card: chip "ENDED EARLY" and "Ended early · Day 10 of 92"; Summary: "WINTER ARC ENDED EARLY" and "Ended early · Day 10 of 92" (instead of "92 days"); Delete Arc in the ⋮ of every finished arc |

Typed words: the field is trimmed, then compared case-sensitively
(`RESTART`, ` RESTART ` valid; `restart`, `RESTAR`, `Restart`, empty
invalid; the same for DELETE). The keyboard opens in capitals, without
autocorrect or suggestions. The confirm button stays disabled (and its
accessible label says why: "Restart Arc. Type RESTART to enable.") until
the word matches, then is busy and single-fire while saving; Back is
blocked while saving. Cancel, Back and leaving write nothing and discard
the typed text. After a committed restart, Back goes to Today.

Midnight while the Restart screen is open re-reads it ("The date changed
…"), so the restart uses the new date; if the arc completed at midnight
the router closes the screen to the completed Arc's summary.

**Additions requiring owner acceptance at Gate F** (no spec text existed,
or the spec text was adapted):

1. The dates line on the Restart screen ("Day 1: today, … · Day 92: …").
2. The Seasonal second line "It uses your 7 habits, goals and order." and
   the Seasonal button "Start Rolling Arc" (the spec names only "Restart
   Arc"; AD12 asks that the wording never say "restart the season").
3. The two pause notes ("The pause you scheduled is cancelled. Nothing was
   paused." / "Your pause ends here. Paused days are never counted.").
4. The radio labels follow spec § 6.6 / the brief ("Keep my old Arc in
   Arc History", "Delete my old Arc…") rather than the § 9.9 wireframe
   ("Keep it in Arc History", "Delete it…"), with the note "Asks again,
   separately, after the restart."
5. "7 habits" counts every copied habit, including those switched off.
6. The delete screen opened from a summary reads "Delete this Arc?" /
   "Delete this Arc" (the arc may not be a "previous" one), and its status
   line reads "Completed" for a completed arc.
7. "This Arc can't be restarted now. Nothing was changed." and "The date
   changed while this was open. These are the new details."
8. Titles are the first line of each screen's scrolling column (headings),
   not one-line app-bar titles, so they wrap at large text (found by the
   layout sweep; spec "everything in one scrolling column").
9. The typed-word instruction is a wrapping line above the field and its
   accessible label; the empty field shows the word as a hint.
10. The Delete button uses dark text on the danger colour (contrast; the
    v1.2 dialog used light text at 2.7:1).

## Tests

| File | Tests | Layer | Covers |
|---|---|---|---|
| `test/data/arc_restart_test.dart` | 37 | R (real in-memory Drift, real services, injected clock) | every row of § 6.7's examples; F2-1, F2-2, F2-3, F2-4/5, F2-6 (with and without activity), F2-7 (open pause, first paused date, after closed pauses), F2-8 (Day 91, Day 92 logged / not logged; never completed, no Summit on later dates, lifecycle and achievement backfill run), F2-9 (season, late join, join day), F2-10; reflection or Minimum Day alone count as activity; the new arc: same ids, titles, types, units, icons, order, on/off, custom habits, latest goals, no revision, fresh Day 1, 0 XP, level 1, no unlock; achievements earned again only by the new arc; the new arc pauses, resumes, completes; refusals with every table identical (T1, T10, F2-14: completed and over-today; setup, ended, unknown, stale id; two concurrent restarts start one arc; all-off configuration); **F2-13 / T5**: SQL-trigger failure on the freeze delete, the session update, the session insert, the first and the last habit insert, plus two read-back mismatches: every table identical, then a retry works once; Journey/streaks of the ended arc; tracking/reflection/edit writes to the ended arc refused; § 12.5 XP split and identities for both arcs on every date d−2…d140 (`other = 0`, ended `today = 0`); Insights; reminders planned from the new Day 1; **T11 / F2-11**: five chained restarts (F2-1, F2-2+F2-6, F2-7, F2-10, F2-8) each exported and restored row for row, `closedOn` never after the export; process death over a file database |
| `test/data/arc_restart_delete_test.dart` | 57 | R | **T7**: deletion removes exactly the ended arc (freezes included), every other row identical; a completed arc the same; **D5**: active, setup, unknown arcs refused (service and repository, the service before reaching the repository); **T8**: a failure at each of 7 cascade tables leaves both arcs identical, retry deletes; Insights, History and a backup after deletion; no deletion ever happens later; **Weekly Review R12**: weeks to `closedOn` complete, later weeks not reached, identical for every later date, the new arc has its own Week 1; **48 generated histories** (Rolling and Seasonal joins, starts around year boundaries and 29 Feb 2028, partial days, goal edits, pauses and resumes, date rollbacks with the restart refused and nothing written, a pause scheduled just before restarting) restarted at a random point and checked against an independent brute-force oracle over the raw freeze rows, the full-snapshot diff and a backup round trip; plus a coverage check that every one of 11 cases occurred |
| `test/domain/arc_restart_rules_test.dart` | 18 | U | the last-lived-day table on synthetic arcs (open, scheduled and closed pauses, Seasonal); `decide`'s refusals in order; the plan; `baselineFrom` (latest revision whatever its date, order, ids); preview flags; typed words (10 inputs + DELETE); wording helpers |
| `test/features/arc_restart_flow_test.dart` | 17 | W (whole app, real router and Drift) | T1: every typed word, keyboard Done, Cancel and Back write nothing, text discarded; Keep: success screen, View previous Arc (Summary "ENDED EARLY"), Back to Today Day 1, History; reminders re-planned; Delete it…: commit first, DELETE screen counts, wrong words, export first and back, Keep it, Back; T6/T7 deletion; T8 failure + Retry; process death between restart and deletion; storage failure + Retry; double tap = one arc; midnight while open; Day 92 + midnight completion closes to the summary; clock behind; Seasonal wording; paused Today; scheduled pause; O11 completed-arc deletion; active-arc delete link; zero counts; the router rules |
| `test/features/arc_restart_read_only_test.dart` | 1 | W | the ended arc's Summary, Journey, Journal, Achievements, all 13 Weekly Reviews and History on 4 dates (closing date to 400 days later): every row of the old arc identical |
| `test/integration/restart_layout_test.dart` | 80 | W | 10 scenes × 7 layouts (360 × 800 at 1× and 2×, 320 × 568 at 1.5×, both landscapes, tablet, 360 × 640 at 1.3×): no exception, overflow, clipped line or sideways scroll; every button and radio tile ≥ 48 dp; the field visible after typing; headings never truncated; Flutter tap-target, label and contrast guidelines at 1× and 2× on every scene; semantics (field labels, disabled-button reasons, "Your old Arc" group, losses as separate nodes with numbers) |
| `test/features/phase5_flow_test.dart` | 2 updated | W | the v1.2 completed-arc delete tests now go through the typed-DELETE screen (owner decision O11); their expectations otherwise unchanged |

Two test doubles that implement `WinterArcRepository`
(`test/domain/arc_lifecycle_test.dart`, `test/support/review_fakes.dart`)
gained a delegating `restart`; no existing assertion changed.

**Defects found by these tests and fixed before the PR:** the enabled
Delete button drew light text on the danger colour (2.71:1, below the
guideline); one-line app-bar titles were cut short at large text (and
"Start a Rolling Arc with this setup" at 1× on 360 dp); the field's
floating label would be cut short at 2×. Titles are now headings in the
scrolling column, the instruction is a wrapping line above the field, and
the button uses dark text.

## Mutation check

Seventeen deliberate defects were introduced one at a time (script in the
session scratchpad), the relevant suites re-run, and the source restored
byte for byte (sha256 checked, and the whole `lib/` and `test/` compared
with a pre-run archive). **16 were detected; 1 is an equivalent mutant.**

| Mutation | Result |
|---|---|
| the last lived day ignores activity (today always lived) | detected |
| clock guard skipped in `decide` | detected |
| shown last day not re-checked | detected |
| shown date not re-checked | detected |
| completed / over-today arc not refused | detected |
| an arc that is not the current one accepted | detected |
| the open freeze kept on the ended arc | detected |
| baseline from the earliest revision instead of the latest | detected |
| activity after `closedOn` accepted | detected |
| read-back check removed | detected |
| old arc's `closed_on` written as today | detected |
| service deletes any status | detected (after adding the "service refuses before the repository" test; the repository guard had masked it) |
| repository's active-arc guard removed | detected |
| typed word not trimmed | detected |
| typed word compared case-insensitively | detected |
| Restart button enabled without the word | detected |
| reminders not re-planned in `runRestart` | **survived: equivalent** — `NextRepApp` already re-plans reminders whenever the active arc changes or `arcRefresh` fires, so the explicit call is a redundant, ordered safety |

## Emulator qualification (disposable AVD)

A new AVD `NextRep12F_API36` (Android 16, API 36, `sdk_gphone64_arm64`,
google_apis, Pixel 6 profile), created for this phase and **deleted
afterwards**; the unrelated AVD on the machine was not touched. Debug
build of this branch only (debug key, `com.nextrep.nextrep`, `1.2.0`/3); no
official APK, no production signing, no physical phone. The clock was set
with `adb root` / `date` (automatic time off); every row was written by
the app through its UI (uiautomator-driven taps). Database checks: a full
row dump of every table on the device before and after each step.

| Step | Observed |
|---|---|
| 1. Start and use a Rolling Arc | Onboarding → Rolling 92-Day → Review & Start → Continue to Start → Confirm & Start on Tue 10 Nov (Day 1, Day 92 Tue 9 Feb 2027); Days 1–4 logged (No Junk Food + 3 glasses): 60 XP, 2 achievements |
| 2. Goal changed, revision pending | Habits → Water 8 → 12: "Saved. Applies from tomorrow."; row `water, 2026-11-14, 12` |
| T1 on device | Restart screen as approved (screenshot); `restart`, `RESTAR`, `Restart` keep "Restart Arc" disabled (its label "Restart Arc. Type RESTART to enable."), `RESTART` enables it; Cancel → **every table identical** |
| 3. Restart (Keep) on Fri 13 Nov | Success: "Your new Arc has started · Day 1 of 92 · Ended early · Day 4 of 92 · 60 XP". Database diff: the old session only `active → ended`, `closed_on = 2026-11-13`; one new active Rolling session 13 Nov – 12 Feb 2027; 7 new habit rows with Water **12** (the pending revision), same order, English/Sleep/Meditation still off. No other row changed (the revision row, XP, unlocks, progress identical) |
| 4. Old Arc | Summary "WINTER ARC ENDED EARLY", "Ended early · Day 4 of 92", "10 Nov – 13 Nov 2026", Total XP 60; Arc History: "ended early · day 4 of 92, Level 1, 60 XP, 2 of 32 achievements" and the new arc "active, 0 XP, 0 of 32" |
| 5. No duplication | New Today: Day 1 of 92, 0 XP, Water 12 glasses; old XP and unlocks only on the old arc |
| Reminders | daily + reflection enabled through the UI (notification permission granted): one per date from 13 Nov |
| 6. Scheduled pause → Restart | Pause from tomorrow (14 Nov): Habits → Restart shows "Your current Arc ends at Day 1 of 92" and "The pause you scheduled is cancelled. Nothing was paused."; Cancel → identical |
| 6. Paused → Restart | Clock Mon 16 Nov: paused Today with "Restart with this setup"; 0 reminders pending while paused; the screen shows "Your pause ends here. Paused days are never counted."; keyboard opens in capitals with the field above it (screenshot); RESTART + keyboard Done with "Delete my old Arc…". Diff: the **open freeze row deleted**, arc 2 `ended`, `closed_on = 2026-11-13` (last lived day before the pause), arc 3 active from 16 Nov |
| 8. Kill between restart and deletion | On the delete screen (counts "1 day of progress and 15 XP", "1 achievement", "0 Journal reflections"): `am kill` + `force-stop`, relaunch → Today "Day 1 of 92", no delete screen, **database identical**, reminders re-planned for the new arc (0 → 27 pending) |
| 7. DELETE flow | History → the ended arc → Arc options → Delete Arc: "Delete this Arc?"; `delete`, `DELET`, `RESTART` keep the button disabled; Keep it → summary, **identical**; then DELETE → back to History. Diff: exactly arc 2's session, habits, progress, XP and unlock removed; arc 1 (ended) and arc 3 (active) and every setting identical |
| 9. Reminders and Focus Guard | reminders re-planned after each restart (counts above); `reminder_preferences`, `focus_guard_preferences`, `focus_guard_selected_apps` and `feedback_preferences` identical in every diff (Focus Guard was not enabled: Usage Access not granted on this AVD) |
| 10. Layouts | 2× text (scrolls, nothing cut), landscape at 2× (width-limited column), 360 × 640 dp at 2× (screenshots); **0 Flutter errors** in logcat |
| End state | `user_version` 7, `integrity_check` ok, no foreign-key violation; version 1.2.0 (3) |

Not run on the emulator: TalkBack (deferred; widget semantics tested),
Focus Guard with Usage Access granted (no Focus Guard code changed; its
tables were compared), the release (R8) build on the device (no native,
dependency or reflection change; CI builds it and the audit passes).

## Permission, package, version, schema and backup audit

| Check | Result |
|---|---|
| Release APK (local, debug key, as CI) | built; `com.nextrep.nextrep`, versionCode 3, versionName 1.2.0 |
| CI's release permission audit, replayed locally | passed: INTERNET, RECEIVE_BOOT_COMPLETED, PACKAGE_USAGE_STATS, WAKE_LOCK, VIBRATE, POST_NOTIFICATIONS and the app-private receiver permission only |
| `android/`, `ios/`, `pubspec.*`, `drift_schemas/`, `lib/core/database/`, `lib/domain/backup/` | untouched |
| Schema / backup | v7; writes 4, reads 1–4 (unchanged code) |
| Network | no new request; `network_boundary_test` passes |
| Dependencies | none added |

## Known limitations and deferred items

- TalkBack was not run (deferred, as for every v1.3 phase); semantics are
  widget-tested (labels, headings, live regions, disabled-button reasons,
  the "Your old Arc" group, the losses read item by item).
- A restart that commits while the success screen's follow-up re-read
  fails reloads the app from storage (as a deletion does); the restart is
  kept.
- Restart is not offered from Today's ⋮ menu: the spec's entry points are
  the Habits screen (reachable in the running and scheduled-pause states)
  and the paused Today.
- "Days of progress" on the delete screen is the arc's elapsed (lived)
  days, as on its summary: a completed arc with sparse activity still
  shows 92 days.
- No sound (12G); no 12H accessibility hardening beyond this phase's
  widget checks; no physical-device or signed-upgrade check (12H/12I).
- The app is English-only.

## Review questions for Gate F

1. Accept the additions listed under "Screens and wording" (1–10)?
2. The Seasonal confirm button reads "Start Rolling Arc" (not "Restart
   Arc"); the typed word stays RESTART. Keep both?
3. "Your 7 habits" includes habits that are switched off (they are copied
   off). Count only the habits that are on instead?
4. The delete screen's "N days of progress" counts the arc's lived days
   (as its summary does), not days with logged activity. Acceptable?
5. A second Restart tap after the commit (or a stale screen) is refused as
   "can't be restarted now" rather than treated as already done. Fine?
6. Restart's success screen and the delete screen use thousands
   separators for XP ("2,430 XP"); other screens print raw numbers. Keep?

## Local validation

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` (all) | **2,183 passed, 0 failed** (`main`'s 1,973 plus 210 new) |
| Native JVM (`:app:testDebugUnitTest`) | 71 / 71 |
| Android debug and release builds | both built; release permission audit passed |
