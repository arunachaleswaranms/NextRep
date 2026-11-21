# Phase 12D: Habit Ordering, Saved Setup and Confirm & Start

## Objective and boundary

The third v1.3.0 user-facing feature, built on the approved
[ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md) §§ 3, 4.1–4.3, 9.1–9.5 and 10
(O1–O5, S1–S7) and [PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md) C1, C2,
AD1–AD4 and L2 (Gate A2 decisions O1 and O2: ordering in setup only; one
saved setup, changes saved as made, plus "Save for Later").

A user can put the habits of an Arc in setup in order (drag, menu or
screen-reader action), leave and come back to a **saved-setup hub**, read
a **Review Setup**, and start only from a dedicated **Confirm & Start**
screen that shows the exact dates.

No schema, migration, backup format, validation, dependency, permission,
network, analytics, version or application-id change. No XP, streak,
Perfect Day, Minimum Day, revision, achievement or 12-habit rule change.
No Freeze, Resume, Restart, deletion beyond the existing Cancel setup,
sound, Focus Guard native or signing work. Version `1.2.0+3`; no release;
no physical phone; no production signing.

## Verified baseline

| | |
|---|---|
| `origin/main` | `fa5ad0f32c76c5cfa8eef6389dbedd88a7a382db`, "Phase 12C: Arc Consistency Calendar (#26)", the expected baseline |
| PRs #24 (12E1), #25 (12B), #26 (12C) | merged (14, 18 and 18 Nov 2026) and on `main` |
| Schema | `AppDatabase.schemaVersion` 7 |
| Backup | `BackupFormat.formatVersion` 4 (reads 1–4) |
| Version | `1.2.0+3`; application id `com.nextrep.nextrep` |
| Existing 12D work | none: no branch, PR or worktree |
| Worktree | `~/labs/NextRep-12D`, new branch `phase/12d-v1.3-setup-control` from `fa5ad0f`; the primary checkout and the other worktrees were not touched |

## Architecture

The saved setup is the existing `WinterArcStatus.setup` session (AD3). No
new state is stored: `DRAFT` and `READY_TO_START` are derived from
`ArcSetup` (`canStart`, the new `blocker`) and today's date.

```
HabitSetupScreen (/setup)          SavedSetupScreen (/setup/saved)  ← launch home
  reorder: drag | menu | a11y        Start Challenge ─┐  Review Setup ─┐
  Review & Start ─────────┐          Continue Editing (push /setup)    │
  Save for Later ─→ hub   │          settings links, Cancel setup      │
                          ▼                          ▼                 ▼
              ReviewSetupScreen (/setup/review)  read-only
                Continue to Start ─→ ConfirmStartScreen (/setup/confirm)
                                       Confirm & Start Challenge / Join Season
                                         → WinterArcService.startWinterArc(confirmedOn:)
                                         → Today
All four read HabitSetupController (one ArcSetup snapshot: session, habits, start
state, today).
```

| File | Role |
|---|---|
| `lib/domain/habit/habit_repository.dart`, `lib/data/drift_habit_repository.dart` | **New** `reorderSetupHabits(sessionId, orderedIds)` |
| `lib/domain/winter_arc/winter_arc_service.dart` | **New** `reorderSetupHabits` (SerialQueue, setup only); `startWinterArc({confirmedOn})`; `SetupBlocker`; `ArcSetup.blocker`, `enabledHabits`, `disabledHabits`, `startPreview`, `withHabits` |
| `lib/core/errors/app_failure.dart`, `lib/shared/formatting/failure_messages.dart` | **New** rules `invalidHabitOrder`, `startDateChanged` and their messages |
| `lib/features/habit_setup/habit_setup_controller.dart` | **New** `move(habitId, index)`; latest-read-wins reloads; `start({confirmedOn})` |
| `lib/features/habit_setup/habit_setup_screen.dart` | A `SliverReorderableList`; Review & Start, Save for Later, Cancel setup; no direct start |
| `lib/features/habit_setup/widgets/habit_toggle_tile.dart` | Drag handle, long-press drag, Move up / Move down, card semantics and custom actions, large-text stacking |
| `lib/features/habit_setup/saved_setup_screen.dart` | **New** hub |
| `lib/features/habit_setup/review_setup_screen.dart` | **New** Review Setup |
| `lib/features/habit_setup/confirm_start_screen.dart` | **New** Confirm & Start |
| `lib/features/habit_setup/setup_labels.dart` | **New** all Gate D wording |
| `lib/features/habit_setup/setup_navigation.dart` | **New** Save for Later, back fallbacks, 600 dp layout |
| `lib/features/habit_setup/cancel_setup.dart` | The existing Cancel setup dialog and `ArcRemoval.cancelSetup`, moved out of the editor so the hub uses the same one |
| `lib/features/habit_setup/widgets/start_button.dart` | **New** a filled action with its "unavailable" reason under it and in its accessible name |
| `lib/app/router/app_router.dart` | Routes `/setup/saved`, `/setup/review`, `/setup/confirm`; `home` / `forSession` of a setup is the hub; redirects |
| `lib/shared/feedback/haptics.dart` | `Haptics.reorderGrip` (pick-up and drop) |
| `.github/workflows/flutter-ci.yml` | A named "Phase 12D tests" step; every existing step unchanged |

## Habit order

### Repository: one transaction

`DriftHabitRepository.reorderSetupHabits(sessionId, orderedIds)`, inside
one `transaction`:

1. the session exists (`sessionNotFound`) and is in setup
   (`sessionNotInSetup`), via the existing `_requireSetup`;
2. reads the session's stored habit ids;
3. `orderedIds` must be exactly that set, each once: a duplicate, missing,
   extra, foreign-session or deleted (stale) id throws `invalidHabitOrder`
   and writes nothing;
4. writes `sort_order = index` for each id whose order differs (ids bound
   as variables; no SQL is built from ids; errors quote no id);
5. any failure (an injected SQLite `RAISE(ABORT)` on the third row in the
   tests) rolls every earlier row back.

Only `sort_order` changes: id, title, type, unit, icon, targets, enabled,
`created_at` and every other table are compared row for row in the tests.
No revision, XP, progress or unlock is written. `sort_order` has no unique
index, and the transaction hides intermediate states.

### Service and controller

`WinterArcService.reorderSetupHabits(orderedIds)` runs on the existing
`SerialQueue` after `_requireSetup()`, so a reorder racing a removal is
serialised: the stale one is refused (`invalidHabitOrder`) and writes
nothing. A running, completed or ended Arc can't be reordered (O5).

`HabitSetupController.move(habitId, index)` builds the order from the
setup on screen, shows it at once (so the dropped card stays where it was
dropped), persists the whole order, then re-reads storage. A failure
re-reads too, so the stored order comes back (O4) and the screen says
"Couldn't save the new order." Every reload is numbered; only the latest
is shown, so an older read can't bring back a changed order. Moving a
habit onto its own place writes nothing.

### Ordering UI

- **Drag handle** (48 × 48 dp, "Reorder Water") starts a drag at once
  (`ReorderableDragStartListener`). A tap on the handle does nothing (a
  defect found by the tests and fixed: it used to switch the habit).
- **Long press** anywhere else on the card starts a drag after the usual
  delay (`ReorderableDelayedDragStartListener`); a short tap still switches
  the habit; a drag never switches, edits or removes.
- **Menu:** Move up · Move down · Edit · Remove. Move up is disabled on the
  first card, Move down on the last, both with one habit (no handle then).
  Disabled and custom habits move like any other.
- **Screen reader:** each card is one node, "Water Intake, 8 glasses, on,
  2 of 7", with custom actions Move up / Move down only where possible.
  After a stored move, "Water Intake moved to position 1 of 7" is
  announced once (`SemanticsService.sendAnnouncement`); nothing is
  announced for a failed or no-op move.
- **During a drag** the menu, switch and moves are disabled.
- **Feedback:** the lifted card gets elevation and a 1.02 scale, eased in;
  with reduced motion they apply at once. A light haptic on pick-up and
  drop.
- **Large text** (> 1.3×): the switch and menu move under the title; the
  handle stays 48 dp. The actions follow the list instead of being pinned
  under it on short screens or at large text.
- All three ways use the one `move` → `reorderSetupHabits` path.

### Where the order shows

The stored order is the order of Habit Setup, the hub's counts, Review,
Confirm, Today, Habits, Journey day sheets, the Weekly Review and share
cards (all read `habitsForSession` / `HabitHistory`, ordered by
`sort_order`). "Reuse last setup" copies `sortOrder`
(`WinterArcService._withConfig`); Phase 12F's Restart is specified to
copy the same way (AD11), so it inherits the chosen order. Adding a habit
appends (`max + 1`); removing leaves a gap that the next reorder closes to
`0..n−1`; editing keeps the place.

## Saved setup

- **Save for Later** (Habit Setup, Review Setup, Confirm & Start; also
  with zero habits) writes nothing, starts nothing and schedules nothing:
  every change was committed when made. It shows the snackbar (a live
  region) and opens the hub with `go`, so the setup screens are not left
  beneath it. Repeating it is harmless.
- **Process death:** the setup is as of the last committed change; only an
  unsubmitted habit form can be lost (spec § 4.2).
- **One draft:** the `single_open_session` index and the existing checks
  are unchanged.

## The hub (`/setup/saved`)

"YOUR WINTER ARC · Your Arc Setup Is Saved", the kind with habit and
"on" counts, and when it starts. Start Challenge (opens Review; disabled
with its reason when the domain says the Arc can't start today), Review
Setup (disabled only after the season ended), Continue Editing (pushes
the editor over the hub, so Back returns), then Reminders, Data & Backup,
Focus Guard (only where supported), Arc History (only with a finished
Arc) and About, and Cancel setup (the editor's own dialog and deletion).
Zero habits: "Add a habit to start." and Continue Editing is the filled
action. Back leaves the app. Reads only; re-read on entry, resume and
midnight.

**Sound & Feedback (dependency for Gate D):** the spec lists it among the
hub's links, but its screen and audio belong to Phase 12G and don't exist
yet. 12D shows no link and no placeholder; 12G adds the link to the hub.

## Launch and routing

| Situation | Opens |
|---|---|
| No Arc | onboarding (unchanged) |
| Choosing an Arc (onboarding / New Arc) | Habit Setup (the editor), as today |
| A setup exists on launch, after process death or a restore | **the hub**, with or without completed / ended history |
| Active Arc | Today; every `/setup…` route redirects to Today |
| No setup on `/setup/saved`, `/review`, `/confirm` | home (onboarding or the latest finished Arc) |
| Unknown `/setup/…` | the existing safe page |

`AppRoutes.home` and `forSession` return `/setup/saved` for a setup;
`redirect` never sends a setup route to another setup route, so nothing
loops and an editing user is never pulled to the hub. Stale reminders with
a setup open the hub. The three routes are top-level (not nested under
`/setup`) so the hub is a home and Review / Confirm sit over whatever
opened them. Review's Edit Setup returns to the editor when opened from it
(`/setup/review?from=editor`), otherwise replaces Review with the editor.

## Review Setup (`/setup/review`)

Read-only: the kind and its dates ("Starts the day you confirm · 92 days",
or the season's dates and day), "YOUR HABITS (n)" in order with number,
goal and Minimum Day goal (count / duration), clock times, "OFF (n)", and
the stored reminder preferences ("Reminders: Daily 07:15 · Reflection off
· Hydration Coach off", "Reminders begin once your Arc starts."). Continue
to Start (disabled with the reason), Edit Setup (filled when there are no
habits), Save for Later. Each habit is one accessible node ("1. Water
Intake. 8 glasses. Minimum 3 glasses."). Its title is the first heading
of the page, not the app bar, so it wraps at large text (the sweep found
it cut off in the app bar).

## Confirm & Start (`/setup/confirm`)

- The only UI that starts an Arc. Heading "Start your Winter Arc?" holds
  the initial keyboard focus; Enter / Space start nothing.
- Shows Day 1 and Day 92 from `ArcSetup.startPreview`, which **is**
  `ArcStartRules.start(session, today: setup.today)` (no second calendar):
  Rolling, "Day 1 Today, Fri 6 Nov 2026" and Day 92 = + 91; Seasonal,
  1 Oct / 31 Dec and "You join today on Day 18 of 92." with "Earlier days
  won't count against you."
- Primary "Confirm & Start Challenge" / "Confirm & Join Season"; 24 dp
  below it, outlined "Save for Later". Back returns to Review. Neither
  starts anything.
- Pressing calls `startWinterArc(confirmedOn: setup.today)`: in the
  service's queue, one clock read decides both the check and the start;
  if today is no longer the date shown, nothing is written and the screen
  re-reads ("The date has changed. Check the new dates, then confirm
  again."). So an Arc never starts on a date the user wasn't shown.
- Busy and non-repeatable while starting (Back too); a double tap starts
  once (the service is idempotent) and opens one Today.
- Domain refusal: its message, the setup re-read, the user stays.
  Storage failure: "Couldn't start. Nothing was changed.", the button is
  usable again; nothing is written (tested with an injected failure).
- Reached directly (deep link), every domain rule still applies: a
  preseason, ended or empty setup shows the disabled reason and no dates.

## Dates, Seasonal rules and midnight

- Rolling: Day 1 is the confirmation date; the days between saving and
  starting are no days of the Arc (`positionOn` → not started), so no
  progress, XP, streak, missed day or journal entry can exist for them.
- Seasonal (unchanged rules): refused before 1 October and after
  31 December from the hub, Review, Confirm and the service; joining on
  31 December is Day 92; a setup is never moved to another year or turned
  into a Rolling Arc.
- Every setup screen re-reads on entry, on resume and at the existing
  midnight tick (`dayChangedProvider`). All dates come from the one
  `ArcSetup` snapshot (the injected `Clock`), never from a widget's
  `DateTime.now()`. Nothing starts by itself at midnight.

## Backup compatibility

Writer stays format 4; readers 1–4; no field or validation changed.
Tested: a Rolling setup with 12 reordered habits (edited custom goals,
three off) round-trips row for row twice and as a format-3 file; a saved
Seasonal setup; a zero-habit setup; the genuine format-1 and format-2
fixtures with a non-contiguous stored order. After a restore the app's
home is the hub, nothing starts, nothing is scheduled and no progress
appears.

## Read-only proof

`test/features/setup_read_only_test.dart`: a populated database (a
completed Arc with progress, XP, day modes, revisions, unlocks and a
reflection; a reused, reordered setup; reminder preferences) is captured
row for row; launch into the hub, Review Setup and its scrolling, Confirm
& Start, Back, Save for Later from all three screens, the editor,
Reminders, Data & Backup, Focus Guard, About, a resume and midnight on
Confirm each leave every table identical and nothing scheduled.
`setup_start_test.dart` proves an actual start changes only the session
row (status, started-at, participation and, for Rolling, its dates).

## Tests

| File | Tests | Covers |
|---|---|---|
| `test/data/setup_reorder_test.dart` | 23 | 0, 1, 2, 8, 12 habits; reversed, same, adjacent, first↔last; disabled, custom, mixed types; no revisions / XP; gaps closed; duplicate, missing, extra, stale, foreign ids; missing, active, completed, ended sessions; mid-transaction rollback; service rollback and recovery; a reorder racing a removal; reorder / edit / add / remove / toggle sequence; Seasonal |
| `test/data/setup_persistence_test.dart` | 10 | Process death after toggle, add template, add custom, edit, remove, reorder, Save for Later; empty and all-off setups; two completed Arcs plus one draft; Reuse last setup keeps the order; backup round trips (format 4 twice, format 3, Seasonal, zero habits, formats 1 and 2) |
| `test/domain/setup_start_test.dart` | 15 | D / D+1 / D+2 / D+5 Rolling; order on Today; date changed forward and back; Seasonal 30 Sep, 30 Sep → 1 Oct, 18 Oct, 31 Dec, 1 Jan; empty / all-off / no setup; double confirmation; storage failure and retry; only the session row changes; blocker order; preview = `ArcStartRules.start` |
| `test/features/setup_control_flow_test.dart` | 19 | The full § 30 journey; menu, screen-reader and drag moves and announcements; one habit; failed reorder; hub empty / all-off / Seasonal (before, Day 18, after, deep link); settings and history links; Cancel setup; Review content and back paths; Confirm focus, Enter, 24 dp, Back, double tap, storage failure, midnight, unseen date change, Seasonal midnights; route guards |
| `test/features/setup_read_only_test.dart` | 1 | The read-only gate above |
| `test/integration/setup_layout_test.dart` | 64 | 9 scenes × 7 layouts; tap-target, label and contrast guidelines at 1× and 2× |
| `test/app/app_routes_test.dart` | +6 | Hub as home, no loops, editor after choosing, active guards, no-setup guards, stale reminders |

Existing tests changed only where 12D deliberately changes behaviour (no
assertion weakened): flows that tapped "Start Winter Arc" / "Join
Seasonal Winter Arc" now start through Review & Start → Continue to Start
→ Confirm (`startFromSetup`); flows that relaunch with a setup now expect
the hub and use Continue Editing to reach the editor; home / `forSession`
expectations for a setup are the hub (`app_routes_test`,
`multi_arc_test`, `restart_restoration_test`, `migration_test`,
`phase2–7`, `phase10a/c`, `phase11d`, `day_one`, `phase11e_combined`).
The on-device `integration_test/` smoke scripts were updated the same way
and compile (`flutter analyze`), but were not run (device only).

Totals at the final local run: **1,822 Flutter tests passed, 0 failed**
(1,684 before the new 12D tests); **71 native JVM tests passed**.

## Accessibility and layout

Automated: card labels with position, custom actions, announcements,
handle labels, disabled-state reasons in accessible names, headings,
one-node review rows and date rows ("Day 1: Today, Friday 6 November
2026"), initial keyboard focus on the Confirm heading, Enter / Space,
48 dp targets (Flutter tap-target guideline and per-button sweep), labels
(labelled-target guideline), no clipped line, nothing wider than 600 dp,
no sideways scrolling, no overflow, on 360 × 800 at 1× and 2×,
320 × 568 at 1.5×, 568 × 320, 800 × 360 at 1.3×, 1280 × 800 and
360 × 640 at 1.3× with reduced motion. Text contrast: Flutter's rendered
contrast guideline passes for every text on the four screens **except the
shared filled-button style** (see limitations).

Not done: physical TalkBack, Switch Access, keyboard or haptics on a
device; no emulator screenshots this phase.

## Known limitations

1. **Reduced motion:** the lift and scale apply instantly, but
   `SliverReorderableList`'s own gap-opening and settle animations use
   fixed internal durations that the built-in widget doesn't expose. They
   stay short; disabling them would need a custom list.
2. **Shared filled-button contrast:** the app-wide `FilledButton` theme
   (text `textPrimary` #F2F6FF on `accent` #4C9BFF, 16 sp bold) measures
   2.61:1, below WCAG for its size. It predates 12D and is used on every
   screen (Let's Begin, Start, …). 12D doesn't restyle the design system;
   the owner may want it addressed in 12H.
3. **TalkBack initial focus** on Confirm & Start is decided by the OS;
   keyboard focus starting on the heading is tested, TalkBack's is not.
4. **Sound & Feedback** link deferred to 12G (above).
5. The editor's header still says "92 days from the day you press Start."
   (existing copy, see Gate D).

## Gate D: owner wording sign-off (PROPOSED, not approved)

The spec is the starting copy. Reconciliation with Gate C: the spec's
Confirm text "Days you don't log will count as missed." is replaced by
"Days with nothing logged show as No progress." so Gate C's approved
"No progress" isn't reversed.

| Where | Proposed copy |
|---|---|
| Editor, under the subtitle (2+ habits) | Hold and drag to put them in your order. |
| Drag handle (accessible name) | Reorder Water |
| Card (accessible name) | Water, 8 glasses, on, 2 of 8 |
| Card menu / actions | Move up · Move down · Edit · Remove |
| After a move (announced) | Water moved to position 1 of 8 |
| Reorder failure | Couldn't save the new order. |
| Editor primary action | Review & Start (replaces "Start Winter Arc" / "Join Seasonal Winter Arc") |
| Editor header, Rolling (existing, unchanged) | 92 days from the day you press Start. *(owner: keep, or "…from the day you confirm the start."?)* |
| Save for Later (button, three screens) | Save for Later |
| Save confirmation | Your Arc setup is saved. / It stays here until you start it. |
| Hub | YOUR WINTER ARC · Your Arc Setup Is Saved · Rolling 92-Day · 8 habits · 7 on |
| Hub, Rolling | Day 1 will be the day you start. |
| Hub / Review, Seasonal before 1 Oct | Season starts October 1. Your setup is saved until then. |
| Hub, Seasonal in season | The season is on Day 42 of 92. Join now and start on Day 42. (Day 1: The season starts today: Day 1 of 92.) |
| Hub, Seasonal over | This season has ended. Cancel this setup to choose a new Arc. |
| Hub actions | Start Challenge · Review Setup · Continue Editing · Cancel setup |
| Hub links | SETTINGS AND HISTORY · Reminders · Data & Backup · Focus Guard · Arc History · About NextRep |
| Empty setup | Add a habit to start. |
| All habits off | Turn on at least one habit to start. (Review list: No habits are on.) |
| Disabled action (accessible name) | Start Challenge, unavailable. Add a habit to start. |
| Review | Review Setup · Rolling 92-Day Arc / Seasonal Winter Arc · Starts the day you confirm · 92 days · YOUR HABITS (7) · OFF (1) · 8 glasses · Min 3 glasses · No habits yet. |
| Review reminders | Reminders: Daily 08:00 · Reflection off · Hydration Coach off · Reminders begin once your Arc starts. · (on read failure) Reminders: couldn't be read just now. |
| Review actions | Continue to Start · Edit Setup · Save for Later |
| Confirm heading | Start your Winter Arc? |
| Confirm summary and dates | Rolling 92-Day Arc · 7 habits · Day 1 Today, Fri 13 Nov 2026 · Day 92 Fri 12 Feb 2027 |
| Confirm, Rolling consequence | Starting begins the count today. Days with nothing logged show as No progress. Not ready? Save it and start another day. |
| Confirm, Seasonal | You join today on Day 44 of 92. Earlier days won't count against you. The season ends Thu 31 Dec 2026. Not ready? Save it and join another day. |
| Confirm buttons | Confirm & Start Challenge (Rolling) · Confirm & Join Season (Seasonal) · Save for Later |
| Date changed before confirming | The date has changed. Check the new dates, then confirm again. |
| Storage failure on start | Couldn't start. Nothing was changed. |
| Other refusals (existing messages) | Pick at least one habit to begin. · The season starts October 1. Your setup is saved until then. · This season has ended. Cancel this setup to choose a new Arc. |
| Cancel setup (existing, unchanged) | Cancel this setup? · Your previous completed Arcs will remain safe. / Your habit choices will be cleared. You can start again whenever you are ready. · Keep Setup · Cancel Setup |
| Sound & Feedback | Not shown in 12D (12G) |

## Deferred and future dependencies

- **12G:** the Sound & Feedback screen, and its hub link.
- **12F:** Restart must copy `sortOrder` (it reuses the "Reuse last setup"
  copy, which already does); no Restart UI was built or tested here.
- **12H:** the shared filled-button contrast; physical TalkBack, Switch
  Access and drag qualification; the remaining reduced-motion animation.

## CI

`.github/workflows/flutter-ci.yml` gains one named step, "Phase 12D
tests", before Focus Guard; every existing step (format, analyze,
migrations, backup formats, lifecycle, Weekly Review, Calendar, Focus
Guard, update checks, release qualification, all tests, debug and release
APKs, native JVM tests, permission audit) is unchanged. The exact-head
run is recorded in the PR.

## Local validation

`dart format --set-exit-if-changed .` clean; `flutter analyze` no issues;
`flutter test` 1,822 passed; `flutter build apk --debug` and `--release`
(debug-signed: this worktree has no `key.properties`) built; `./gradlew
:app:testDebugUnitTest` 71 passed; the CI permission audit, replayed on
the local release APK, passed (exact expected set). `git diff --check`
clean. No change under `pubspec.*`, `android/`, `ios/`,
`lib/core/database/` or `lib/domain/backup/`.
