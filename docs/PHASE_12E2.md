# Phase 12E2: Freeze and Resume

## Objective and boundary

The fourth v1.3.0 user-facing feature: an active **Rolling** Arc can be
paused from tomorrow and resumed on a later day, exactly as approved in
[ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md) §§ 3, 5, 9.6–9.8 and 10
(Z1–Z12) and [PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md) AD5–AD9,
AD19, F1, L3 and L7 (F1), on the schema-v7 foundation of
[PHASE_12E1.md](PHASE_12E1.md).

No schema, migration, backup format, validation, dependency, permission,
network, analytics, notification channel, reminder type, version or
application-id change. No XP, streak, Perfect Day, Minimum Day, revision
or achievement rule change. No Restart, deletion or sound (12F, 12G).
Focus Guard's native code and worker are unchanged. Version `1.2.0+3`;
no release; no physical phone; no production signing.

## Verified baseline

| | |
|---|---|
| `origin/main` | `dcde6b3538f70429f4aecf369fa84b07444e7f20`, the squash merge of PR #27 (Phase 12D, final head `d7644199…`), merged 22 Nov 2026 06:30 UTC; nothing landed after it |
| Post-merge CI | run [44994020321](https://github.com/arunachaleswaranms/NextRep/actions/runs/44994020321) on `dcde6b3`: both jobs passed |
| PRs | none open; #24 (12E1), #25 (12B), #26 (12C), #27 (12D) merged |
| Release | v1.2.0 published; source `1.2.0+3` |
| Schema / backup | `AppDatabase.schemaVersion` 7; `BackupFormat.formatVersion` 4 (reads 1–4) |
| Package | `com.nextrep.nextrep` |
| Worktree | `~/labs/NextRep-12E2`, branch `phase/12e2-v1.3-freeze-resume`, new from `origin/main`. Every other worktree (11B–12E1) was clean and was not touched |

`PROJECT_STATE.md` still described PR #27 as "not merged"; it is
corrected here from the PR's merge record.

## Architecture

```
Today ⋮ "Pause Arc" ─┐                       ┌─ Resume sheet ◄─ paused Today card
Habits "Pause Arc" ──┴─► Pause sheet          │
       │ (preview: service.pausePreview)      │ (preview: service.resumePreview)
       ▼                                      ▼
runPauseAction ──► ArcPauseService.pause / cancelPause / resume   (SerialQueue)
       │                       │
       │                       ▼
       │        WinterArcRepository.changeFreezes  ── one Drift transaction:
       │          read session + freezes + lastActivityDate
       │          ArcPauseRules.{pause,cancel,resume}  (pure, one clock read)
       │          apply FreezeChange (≤ 1 arc_freezes row, + end_date on Resume)
       │          read back: == change.applyTo(before) and problemWith == null
       ▼
ReminderService.reconcile (re-plan at once) → arcRefresh (every screen re-reads)
```

| File | Role |
|---|---|
| `lib/domain/winter_arc/arc_pause.dart` | **New.** `PauseBlocker`; the sealed `FreezeChange` (`FreezeUnchanged`, `ScheduleFreeze`, `DeleteOpenFreeze`, `CloseFreeze`) with `applyTo`; the pure `ArcPauseRules` (`blockerOn`, `frozenFromFor`, `pause`, `cancel`, `resume`); `ArcPauseFacts` (`openFreeze`, `scheduledPauseOn`, `pausedDaysThrough`); `PausePreview`, `ResumePreview` |
| `lib/domain/winter_arc/arc_pause_service.dart` | **New.** `ArcPauseService`: previews (read-only) and the three writes, serialised, each one `changeFreezes` transaction with one clock read |
| `lib/domain/winter_arc/winter_arc_repository.dart`, `lib/data/drift_winter_arc_repository.dart` | `changeFreezes`: the transaction above. `updateSession` still never writes freezes |
| `lib/data/drift_arc_activity_repository.dart` | The `lastActivityDate` query extracted to `queryLastActivityDate`, so the Freeze transaction re-checks the clock guard inside itself. Same SQL, same tables (never goal revisions) |
| `lib/core/errors/app_failure.dart`, `lib/shared/formatting/failure_messages.dart` | Rules `pauseUnavailable`, `pauseDateChanged`, `clockBehindHistory`, `pauseAlreadyStarted`, `notPaused`, `resumeDateChanged` and their messages |
| `lib/app/dependencies.dart` | `arcActivityRepositoryProvider`, `arcPauseServiceProvider` |
| `lib/features/arc_pause/` | **New.** `pause_labels.dart` (all wording), `pause_actions.dart` (`runPauseAction`, `pauseEntryProvider`), `pause_sheet.dart`, `resume_sheet.dart`, `paused_arc_card.dart` (`PausedArcCard`, `PauseScheduledBanner`) |
| `lib/features/today/today_screen.dart` | Overflow ⋮ "Pause Arc" (only when offered), the scheduled banner with Cancel pause, and the paused Today (card + Focus Guard) |
| `lib/features/habits/habits_screen.dart`, `lib/domain/progress/habit_tracking_service.dart` | "Pause Arc" entry; `HabitSettings.pausedToday` / `waitsForResume` and their wording |
| `lib/features/journal/journal_screen.dart` | "Paused" note instead of "complete" on a paused date |
| `lib/features/summary/*`, `lib/features/history/widgets/arc_history_tile.dart` | "Paused N days" (F11) |
| `.github/workflows/flutter-ci.yml` | A named Phase 12E2 test step (the convention of 12B–12D) |

There is **no second lifecycle engine**: every date question goes through
12E1's `WinterArcSession` mapping (`isFrozenOn`, `dayNumberOf`,
`dateOfDay`, `positionOn`, `isParticipatingOn`, `isOverOn`,
`participatingDatesThrough`) and 12E1's `ArcClockGuard`. The resume end
date is `endDate + (R − frozenFrom)`; `WinterArcRules.problemWith` then
requires it to equal `start + 91 + closed paused days`.

## Rules as implemented

| Rule | Implementation |
|---|---|
| F1 active Rolling only | `blockerOn`: `notActive` (setup, completed, ended), `seasonal`; the service refuses (`pauseUnavailable`) whatever the UI shows |
| F2 tomorrow, always | `frozenFrom = today + 1` from the transaction's own clock read; the sheet's shown date must equal it (`pauseDateChanged` otherwise). A goal revision never moves it |
| F2a clock guard | `ArcClockGuard.check` inside the transaction with `queryLastActivityDate` (progress, day modes, XP, reflections, unlocks; never revisions) and the last `resumedOn`; refusal stores nothing and the sheet names the dates |
| F3 Cancel | deletes the open row only while `today < frozenFrom` (after midnight `pauseAlreadyStarted`), and — since Gate E2 review R1 — only on the scheduling day, with the clock guard holding and the clock not earlier than `requestedAt` or the Arc's latest recorded instant (`cancelPauseUnavailable` otherwise); all checked inside the transaction |
| F4 not on Day 92 / while scheduled / paused | `blockerOn`: `lastDay`, `scheduled`, `paused`; the ⋮ entry and the Habits entry are hidden |
| F5 Resume | `resumedOn = today`, `endDate += today − frozenFrom`, one transaction; on the first paused date the interval would be empty, so the row is deleted (addendum § F3) |
| F6 read-only while paused | existing write guards (`_trackableSession`, `ReflectionService`) refuse a paused date; the paused Today has no habit tile, Minimum Day, Edit habits or share; Habits and the Journal say "paused" |
| F7 no XP, no other row | `changeFreezes` writes at most one `arc_freezes` row and the session's `end_date`; tests compare every other table |
| F7a waiting revision | untouched; `configOn` finds it on the resume date |
| F8 streaks | unchanged `StreakRules` over `participatingDatesThrough` |
| F9 reminders | `runPauseAction` reconciles at once after each stored change (the planner already skips paused dates) |
| F10 Focus Guard | untouched; the sheet says so and links to its settings where supported |
| F11 paused days | Summary and the Arc History card: "Paused N days" |
| F12 never completes | 12E1's `isOverOn` |
| F13 a lived day between pauses | follows from F2 + F5 + the `lastResume` guard; validated by `problemWith` |

A repeated request (double tap, a race with another request) finds its
own result stored and is `FreezeUnchanged`: Freeze for the same start,
Resume of an Arc already running today, Cancel with nothing scheduled.
The sheets also disable their button while saving (`PrimaryButton.busy`).

## Screens and wording

All new copy lives in `lib/features/arc_pause/pause_labels.dart`.

| Surface | Wording (approved wireframe text where it exists) |
|---|---|
| Entry | Today ⋮ "Pause Arc"; Habits "Pause Arc" |
| Pause sheet | "Pause your Arc"; "From tomorrow, Sat 14 Nov, your Arc stops counting days until you resume."; bullets "Today (Day 25) still counts. You can finish it, or use a Minimum Day." · "Paused days are never missed days." · "You continue on Day 26 when you resume; your last day moves later." · "Reminders pause. Focus Guard keeps its own schedule." + "Focus Guard settings"; "Pause from tomorrow" / "Not now" |
| Refusal (clock) | "Your phone's date (9 Mar) is earlier than your latest logged day (10 Mar). You can pause from 10 Mar. Nothing was changed." (other bounds: "the day your Arc last resumed", "your Arc's first day") |
| Errors | "Couldn't pause. Nothing was changed." + Retry; date changed: "The date changed while this was open. These are the new dates." |
| Banner | "Pause starts tomorrow. Today still counts." · "Cancel pause"; after a clock move back: "Pause starts Sat 14 Nov. Today still counts." and, instead of Cancel, "This pause can only be cancelled on Fri 13 Nov, the day it was set." (R1) |
| Cancel | snack "Pause cancelled. Nothing was paused."; after midnight "Your pause has already started. Resume when you are ready."; clock behind (R1) "Your phone's date or time is earlier than when this pause was set, so it can't be cancelled now. Nothing was changed." |
| Paused Today | "Arc paused"; "Paused since Sat 14 Nov · 6 days" (on the first date "Paused since today, Sat 14 Nov"); "You stopped after Day 25 of 92."; "When you resume, that day becomes Day 26."; "Paused days don't count against you."; "Resume Arc"; Journey › Journal › Arc History ›; Focus Guard card below |
| Closed pause (date moved back) | "Paused Sat 14 Nov – Thu 19 Nov"; "Continues on Fri 20 Nov."; no Resume |
| Resume sheet | "Resume your Arc?"; "Today, Fri 20 Nov, becomes Day 26 of 92."; "Your new last day is Mon 25 Jan 2027."; "You paused for 6 days." (+ "Paused days in this Arc: N days." after earlier pauses); "Resume today" / "Not yet"; failure "Couldn't resume. Your Arc is still paused." + Retry |
| Habits while scheduled / paused | "Your Arc is paused from tomorrow. Goal and on/off changes apply when you resume, …"; "When you resume: 10 glasses · …"; "Off when you resume"; snack "Saved. Applies on your next challenge day." (R3); paused: "Your Arc is paused. Habits can be edited again when you resume." |
| Journal while paused | "Your Arc is paused. Reflections continue when you resume." |
| Summary / History | "Paused 9 days"; date range "1 Mar 2027 – pause scheduled" before the pause begins, "– paused" while it is in effect (R2) |

Dates are short on screen ("Sat 14 Nov", the year only when it differs
from today's) and read in full by a screen reader ("Saturday 14 November
2026"). Above 1.3× text the paused card's links stack one per line.

**Deviations and additions for Gate E2 review** (no spec text existed):
the second Resume line for earlier pauses; "No days were paused." on the
first paused date; the two extra clock-guard bounds; the dated banner
after a clock move; the Habits / Journal paused and waiting wording; the
Cancel snack. "Restart with this setup ›" on the paused Today is **not**
shown (Restart is Phase 12F). The share button is hidden on the paused
Today (there is no day's progress). The Focus Guard sentence and link are
hidden where Focus Guard is unsupported (iOS). "No progress" never
labels a paused date: paused dates have no cell and no class.

## Tests

| File | Tests | Layer | Covers |
|---|---|---|---|
| `test/data/arc_pause_test.dart` | 53 | R (in-memory Drift, real services, injected clock) | Freeze on Day 1 / 25 / 91, today still trackable, Minimum Day, reflection, edit (Z2, Z10); Day 92 (Z1, F1-9); Seasonal, setup, completed, ended, scheduled, paused, before start (Z1); stale sheet; same-day cancel = every table identical; cancel after midnight; midnight with no write and every write refused on a paused date (F6); never completes (Z6); no missed day in Journey / Calendar / summary (Z3); the worked example (Day 11 on 20 Mar, 9 Jun, completes 10 Jun) (Z5); resume on the first paused date; Day 91 (F1-8); refusals; duplicate and concurrent requests; F1-1 … F1-4 (Z11); clock guard F1-6, F1-7, F1-10 ×2 (Z12); time-zone moves before a pause, into a closed pause, DST, year boundary, leap day; five cycles (F1-11); F13; a 400-day pause; streaks 5 + 2 = 7 (Z7); failure injection (SQL triggers) on the insert, on the end date after the row was closed, on the row update, on the delete, plus invariant and read-back rollbacks; reminders (Z8) incl. Hydration and a Day-91 pause; process restart over a file database; format-4 backup of scheduled, open + revision (F1-5) and closed pauses, restored row for row; Weekly Review and Calendar paused / resumed (R10, R11); zero-freeze identity (Z9); previews |
| `test/domain/arc_pause_rules_test.dart` | 9 | U | every blocker; pause, cancel, resume decisions and refusals; previews; **2,000 generated histories** (up to 12 pause/resume cycles, gaps up to 449 days, 2026–2030 starts) against 12E1's independent calendar walk: valid at every step, lived days never move, end = start + 91 + paused, F13, no reminder in an open pause; wording |
| `test/features/arc_pause_flow_test.dart` | 11 | W (whole app, real router and Drift) | Not now / barrier / system Back write nothing; pause, banner, Cancel, pause from Habits; midnight with the app open; Resume sheet, Not yet, Resume; reminders re-planned with the continuing day numbers; History "Paused 6 days"; Seasonal and Day 92 hide the entry; clock-guard refusal; failed pause and failed resume (+ Retry); midnight while either sheet is open; Focus Guard link, card and untouched scheduler / table; closed-pause rollback; Journal and Habits paused (read-only, no editor, no Pause entry, nothing written); the date moving back while the Resume sheet is open |
| `test/features/arc_pause_read_only_test.dart` | 2 | W | **every table identical** after the paused Today, Resume sheet (Not yet, dismissed), Journey path and calendar, Journal, Arc History, reminder settings and midnight; a completed Arc with pauses: Summary and History show "Paused 9 days" and write nothing |
| `test/integration/pause_layout_test.dart` | 51 | W | 7 scenes (Pause sheet, refusal, banner, paused Today, closed pause, Resume sheet with 2029 dates and two pauses, failed Resume) × 7 layouts (360 × 800 at 1× and 2×, 320 × 568 at 1.5×, both landscapes, tablet, 360 × 640 at 1.3×): no exception or overflow, no clipped line, nothing sideways, every button ≥ 48 dp; Flutter tap-target, label and contrast guidelines at 1× and 2× for all 7; headings, spoken dates and the labelled Cancel |

**Defects found by these tests and fixed before the PR:** the paused
card's link row overflowed by 50 px at ≥ 1.5× text (now one link per line
above 1.3×, the spec's large-text rule, with a flexible label); "Arc
paused" was not exposed as a heading (now a semantics container).

**Mutation check.** Twelve deliberate defects were introduced one at a
time and the relevant suites re-run; **all 12 were detected**: pause
start `+2`, clock guard skipped, end date not moved, Day 92 allowed, an
empty interval closed instead of deleted, the end-date write dropped,
the read-back check removed, the heading flag removed, no refresh after
an action, a Seasonal Arc allowed, a stale resume date accepted, Cancel
after midnight allowed. The sources were restored byte for byte.

**Pre-PR independent review** (a separate reviewer given the diff and
the specs, not this record): nothing critical or important. Minor
findings and what was done:

| Finding | Action |
|---|---|
| A refusal other than date / unavailable / clock guard (e.g. a rolled-back change) re-read the Pause sheet silently | fixed: "Couldn't pause. Nothing was changed." + Retry |
| A failed re-read left the old dates on a sheet | fixed: the sheet shows its error and Retry instead |
| A date moved back before the pause while the Resume sheet was open showed two contradictory lines | fixed: only "Your Arc is not paused today." (new flow test) |
| "Paused N days" on the History card didn't update at midnight | fixed: the tile watches the day change |
| `findsNothing` checks on the lazy Habits list could pass unbuilt | fixed: the list is scrolled to its last habit first; the paused Habits screen now has a UI test |
| Cancel pause has no clock guard: after a date rollback to before a pause that has already begun, Cancel deletes it and its dates become unlived days | **not changed**: spec F3 allows Cancel whenever `today < frozenFrom`; recorded as review question 4 |

Two existing test doubles that implement `WinterArcRepository`
(`test/domain/arc_lifecycle_test.dart`, `test/support/review_fakes.dart`)
gained a delegating `changeFreezes`; no existing assertion changed.

## Emulator qualification (disposable AVD)

A new AVD `NextRep12E2_API36` (Android 16, API 36, `sdk_gphone64_arm64`,
google_apis), created for this phase and deleted afterwards; an unrelated
AVD on the machine was not touched. Debug build of this branch only (debug
key, `com.nextrep.nextrep`, `1.2.0`/3); no official APK, no production
signing, no physical phone. The Arc was started through the UI on a
back-dated clock (`adb root`, `auto_time 0`, `date`), so every row was
written by the app. Database checks: the app database pulled with `adb
root` and every table hashed; reminders: NextRep's pending
`ScheduledNotificationReceiver` alarms in `dumpsys alarm`, per date.

| Step | Observed |
|---|---|
| Start | Rolling Arc via Choose your Arc → Review & Start → Confirm & Start on Tue 10 Nov (Day 1, last day 9 Feb 2027); Day 1 logged (+15 XP); clock to Sun 22 Nov = **Day 13** |
| Reminders | daily, reflection and Hydration Coach on through the UI: **55 pending** over 14 dates |
| Pending revision | Habits: Water 8 → 10 → revision `water, 2026-11-23, 10` ("From tomorrow") |
| Pause sheet (from Habits) | the approved text with "Mon 23 Nov", Day 13 / Day 14 and the Focus Guard link (screenshot) |
| Pause from tomorrow | row `(1, 2026-11-23, open)`; the revision dated the same day **did not move it**; revision, XP and progress rows unchanged; pending **55 → 5** (today's only); Habits now "When you resume: 10 glasses" |
| Banner, Cancel, re-pause from Today ⋮ | banner as specified; Cancel → row deleted, "Pause cancelled. Nothing was paused.", pending back to **55**; ⋮ Pause Arc → row again, pending **5** |
| Today still counts | No Junk Food completed after scheduling: +15 XP on 22 Nov |
| Focus Guard on | Usage Access granted, Chrome, 1 h; WorkManager job present; `focus_guard_preferences` recorded |
| **Midnight with the app open** | clock 23:58:30, app foregrounded; at 00:00 Today switched by itself to "Arc paused · Paused since today, Mon 23 Nov · You stopped after Day 13 of 92 · … Day 14"; **every table identical** across midnight; **0 pending** |
| Stale Undo across midnight | a snackbar from the day before stayed visible; tapping its Undo on the paused date was refused ("Your Winter Arc is not running today."), every table identical (see limitations) |
| App kill | `force-stop` + relaunch: paused, identical, 0 pending |
| Reboot | `adb reboot`: 0 NextRep alarms after boot; the emulator's clock came back as the host's (22 Nov, before the pause), and the app correctly showed **Day 13 with the banner** (spec § 5.4), planning only that day's 2 reminders; identical |
| Paused views (26 Nov) | "Paused since Mon 23 Nov · 3 days"; Arc History "Paused 3 days"; Journey "Paused after Day 13 of 92", Day 14 "Upcoming"; Calendar pause row "Paused since 23 Nov", no paused cell, only genuinely unlogged days read "No progress"; Week 2 review "Paused since Monday 23 November", "Day 14. Upcoming. Its date is set when you resume."; identical after all of them |
| 2× text | paused card (links one per line) and Resume sheet screenshots: nothing clipped |
| **Resume** | sheet: "Today, Thu 26 Nov, becomes Day 14 of 92. Your new last day is Fri 12 Feb 2027. You paused for 3 days." → Resume today → **Day 14 of 92**, Water **10 glasses** (the waiting revision, its row unchanged); `arc_freezes (2026-11-23, 2026-11-26)`, `end_date` 2027-02-09 → **2027-02-12**; XP and Focus Guard rows unchanged; pending **54** from 26 Nov on. The Day-14 achievement was then unlocked by the app's normal reconciliation, dated **26 Nov** (Day 14's mapped date, not a paused date) |
| Focus Guard | still exactly one WorkManager job (WorkManager rotates its id), preferences identical |
| Clock back into the closed pause (24 Nov) | "Paused from Monday 23 November 2026 to Wednesday 25 November 2026 … Continues on Thursday 26 November 2026", no Resume; identical; no reminder for 24–25 Nov |
| Landscape, small screen at 2× | Pause sheet width-limited and scrolling, every action reachable; no Flutter error in logcat; Back wrote nothing |
| **Reboot while paused** (2nd cycle) | paused from 27 Nov; clock 28 Nov; reboot; date set again before the first launch: "Arc paused · Paused since Fri 27 Nov, 1 day · Day 14 … Day 15"; the 2 alarms left were the scheduling day's (26 Nov, a challenge date) and were cleared on launch |
| Resume on 30 Nov | **Day 15 of 92**, last day **Mon 15 Feb 2027**, "Paused days in this Arc: 6 days."; two closed rows; revision and XP unchanged; **55** pending re-planned |

Not run on the emulator: a real time-zone change (date moves were
simulated with the clock; LocalDate arithmetic has no time zone), TalkBack
(deferred; semantics are widget-tested), the minified release build (no
native or dependency change in this phase; CI builds it and the audit
passes).

## Permission, package, version, schema and backup audit

| Check | Result |
|---|---|
| Release APK (local, debug key, as CI) | `com.nextrep.nextrep`, versionCode 3, versionName 1.2.0 |
| CI's release permission audit, replayed locally | passed: exactly INTERNET, RECEIVE_BOOT_COMPLETED, VIBRATE, POST_NOTIFICATIONS, PACKAGE_USAGE_STATS, WAKE_LOCK and the app-private receiver permission; no forbidden permission, service, WebView or exported provider; R8 keeps intact |
| Files under `android/`, `ios/`, `pubspec.*`, `drift_schemas/`, `schema_versions.dart`, `app_database.dart`, `lib/domain/backup/` | untouched (one documentation comment in `tables.dart` only; generated code unchanged) |
| Schema / backup | v7; writes 4, reads 1–4 |
| Network | no new request; `network_boundary_test` passes |
| Notifications | no new channel, permission or type; exact alarms not used |

## Gate E2 review corrections (R1–R3)

Review of head `5472331` (owner, 22 November 2026). The wording listed
under "Deviations and additions" is **accepted** ("Paused days in this
Arc: N days.", "No days were paused.", "Pause cancelled. Nothing was
paused.", the Habits and Journal paused explanations, the clock-guard
descriptions), except the one change of R3. Resume on the first paused
date still deletes the empty interval.

**R1 — Cancel pause against a clock moved back.** Before, Cancel only
needed `today < frozenFrom`, so after a pause had begun, setting the
phone's date back made Cancel delete it, turning its dates into unlived
challenge days. Now `ArcPauseRules.cancel`, run inside the
`changeFreezes` transaction with facts read in it, refuses and writes
nothing unless:

1. the pause has not started (`today < frozenFrom`);
2. today is the scheduling day, `frozenFrom − 1`;
3. the Arc clock guard holds (participation start, latest activity,
   latest resume);
4. the clock reading is not earlier than the stored `requestedAt`
   (absolute instants, one-second stored precision, so a time-zone change
   neither helps nor hurts);
5. the clock reading is not earlier than **the latest instant anything of
   the Arc was written** (`queryLatestRecordedInstant`: the Arc's
   creation and start, freeze request and resume times, habits, goal
   revisions, progress, day modes, XP, unlocks, reflections). This is the
   narrow addition found by reading the source: within schema v7 every
   Arc write already stores an instant, so any write after the pause was
   set (e.g. a habit logged that evening) also bounds a rollback. App-level
   tables (reminders, Focus Guard, sound settings) are not consulted, to
   keep Arc rules independent of them (AD9).

The banner offers Cancel only on the scheduling day (other dates: "This
pause can only be cancelled on Fri 13 Nov, the day it was set."); a
refusal on that day shows "Your phone's date or time is earlier than when
this pause was set, so it can't be cancelled now. Nothing was changed."
Freeze, Resume, the next-day rule and every stored row are unchanged; a
repeated Cancel is still `FreezeUnchanged`.

**Residual limitation (not removable offline).** If a pause has begun
and the device clock is set back to the scheduling day, to a time after
the pause request and after every stored write of the Arc, with nothing
written since, Cancel succeeds: nothing stored can show that midnight
passed. The test "moved back to the scheduling day … the documented
residual limitation" asserts this behaviour explicitly. No trusted clock
and no new persistence were introduced.

**R2 — date ranges.** `arcDateRange` / `arcHeading` take the caller's
`today` (from the screen's own injected state: `JournalView.today`,
`JourneyOverview.today`, `WeeklyReview.date`, `SummaryView.today`,
`ArcSetup.today`, and `clockProvider` in the History tile and the restore
dialog; no new `DateTime.now()`). An open pause that starts after today
reads "1 Mar 2027 – pause scheduled", one in effect "– paused"; closed,
completed and ended ranges are unchanged. The History tile now rebuilds at
midnight. Consumers checked: Arc History tile, Summary heading and delete
dialog, Journal, Journey and Weekly Review headings, Habit Setup (setup
arcs have no pause), the restore confirmation.

**R3 — wording.** "Saved. Applies when you resume." → "Saved. Applies on
your next challenge day." Stored revision behaviour unchanged (still dated
tomorrow).

| New tests | Count | Covers |
|---|---|---|
| `test/data/arc_pause_test.dart`, group R1 (real Drift) | 9 | ordinary later-same-day Cancel (every table identical); 23:59:59 vs 00:00:00; moved back before the scheduling day, before and after the pause began; before `requestedAt` and the residual limitation; behind a later habit log; behind stored activity and a later resume (synthetic damaged data); repeated and concurrent Cancel; failure injection + retry; process restart over a file database (same evening, after midnight, moved back before the request) |
| `test/domain/arc_pause_rules_test.dart` | 1 | every R1 check, the same instant in UTC, a time-zone move west that only the scheduling-day check catches, `cancelOfferedOn` |
| `test/features/arc_pause_flow_test.dart` | 3 | banner without Cancel and its explanation; refusal message with nothing written; History "pause scheduled" → "paused" at midnight; R3 snack with the revision still dated tomorrow |
| `test/shared/arc_labels_test.dart` | 2 | scheduled, in effect, rolled back, none, cancelled, closed (several dates), completed, heading |
| `test/integration/pause_layout_test.dart` | 7 | the no-Cancel banner on all 7 layouts (plus the guideline checks) |

Mutation check of the corrections: removing the scheduling-day check,
the `requestedAt` check, the latest-write check, the guard, the
latest-instant read, or the scheduled/paused distinction — all 6 detected
(the scheduling-day check only after the time-zone case was added).

## Known limitations

- Cancel pause cannot detect a clock set back to later on the scheduling
  day after the last stored write (R1 residual limitation).
- A snackbar shown before midnight (e.g. "+15 XP · Undo") can stay on
  screen after the day changes; its Undo is then refused safely on a
  paused date (observed on the emulator, nothing written). Pre-existing
  behaviour, not changed here.
- Restart from the paused screen is Phase 12F.
- The app is English-only; "long localized dates" were exercised with the
  longest English forms (full weekday and month names, a 2029 year).
- TalkBack was not run (deferred, as for every v1.3 phase).

## Review questions for Gate E2

1. The added wording — **accepted** at review, with the R3 change.
2. "– paused" before the pause begins — **resolved by R2**.
3. Resume on the first paused date deletes the pause (addendum § F3);
   the sheet then says "No days were paused." Acceptable?
4. Cancel after a clock rollback — **resolved by R1**, with the
   residual limitation stated there.

## Local validation

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` (all) | **1,951 passed, 0 failed** at `5472331` (the 1,825 of `main` plus 126 new); **1,973 passed, 0 failed** after the Gate E2 corrections (+22) |
| Native JVM (`:app:testDebugUnitTest`) | 71 / 71 |
| Android debug and release builds | both built (again after the corrections); CI's permission audit replayed: passed |
