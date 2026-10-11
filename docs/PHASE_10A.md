# Phase 10A: Daily Integrity & Sleep UX

## Objective

The first of the v1.1 phases. Three changes:

1. A Minimum Day can return to full targets while it is still today.
2. Achievements that today's reversible changes earned stay consistent when
   those changes are undone.
3. Sleep Before Target says plainly that today's check-in is last night's
   bedtime.

Nothing else from v1.1 is in this phase (see [Deferred](#deferred)). The
version stays **1.0.0+1**. No tag, no GitHub Release, no APK.

## Baseline

| | |
|---|---|
| `main` | `b3f9c5caaa26759b757673f85535ed1f9b59623a` (PR #10, Phase 9), clean tree, matches the expected baseline |
| `v1.0.0` tag | present, on `b3f9c5c` |
| Branch | `phase/10a-daily-integrity`, from `b3f9c5c` |
| Main CI | Flutter CI run 37815351893 on `b3f9c5c`: success |

## 1. Minimum Day: reversible on the same day

### Before (v1.0.0)

Minimum Day was one-way: once today was switched, it stayed a Minimum Day.

### After

`NORMAL DAY ⇄ MINIMUM DAY`, for the current challenge date only, while it is
still today. Past days never change.

**Activation** (`HabitTrackingService.activateMinimumDay`) is unchanged:
today only; effective targets drop to each habit's minimum; progress values
stay; habits that meet the reduced target complete and earn their XP; a
Minimum Day is never a Perfect Day; repeating it is a no-op; a day that is
already Perfect can't be switched.

**Return to full targets** (`HabitTrackingService.returnToFullTargets`):

- The date must be today and the arc active and running today
  (`_trackableSession`, the same gate as every write). A day that has rolled
  over, or any past or future date, is rejected with `staleDay`; a
  completed arc with `arcNotRunningToday`.
- It acts only on a Minimum Day. On a normal day it is a no-op (value
  `false`, no writes), so a repeated request is safe.
- It requests `DayChange(mode: DayMode.normal)` and
  `DayRules.settle` does the rest, in the same `commitDay` transaction as
  every other change to today. No XP logic exists in the controller or UI.
  - Progress values are never changed.
  - Completion is re-evaluated against the full targets.
  - Habit XP no longer earned is revoked; XP still earned stays.
  - If every full target is already met, the day becomes a Perfect Day and
    earns exactly one Perfect Day bonus (`perfect_day:<date>`, the existing
    idempotency key).
- Clock-time habits (Sleep Before) have the same target on both kinds of
  day, so returning changes nothing for them.

Because the ledger is a function of the day's state, any sequence of
activations and returns ends with exactly the XP the final state is worth.
A test toggles three times, twice each way, and checks the ledger row by
row.

**When can a return create a Perfect Day?** Increments stop at the
effective target, so on a Minimum Day a numeric habit can't go past its
minimum. A return creates a Perfect Day when the numeric habits met their
full targets before the switch and the rest (done / not-done habits and
clock-time habits, whose target is the same on both kinds of day) are
completed during the Minimum Day.

### Persistence

The mode is stored in the existing `day_modes` table by the existing upsert.
A day returned to full targets gets an explicit `normal` row (with its
`changed_at`). Every reader already goes through `ArcRecords.modeOn`
(`modes[date] ?? normal`), so an explicit `normal` reads exactly like a
missing row. `normal` is a `DayMode` value v1.0.0 already knows: the
format-2 backup codec and validator accept it, so a backup with such a row
restores into v1.0.0 as well. No table, column, migration or backup change.
Minimum Day rows written by v1.0.0 stay valid as they are.

### UX

- After **Switch to Minimum Day**, a snackbar says **"Minimum Day
  activated"** with an **Undo** action. Undo calls the domain operation,
  pinned to the date it was offered for: if the day has rolled over, the
  stale-day rejection wins ("It's a new day — Today has been refreshed.")
  and yesterday stays a Minimum Day. The label is "Undo", the casing every
  other snackbar action in the app already uses.
- While today is a Minimum Day, the banner offers **"Return to full
  targets"** (a 48 dp text button). It asks first:
  - **Return to full targets?**
  - "Your progress stays as it is. Habits that no longer meet their full
    targets may become incomplete, and XP will be adjusted to match."
  - **Cancel** · **Return to full targets**
- On success Today re-reads persisted state: full targets, unchanged
  progress, the banner gone, "Having a rough day?" offered again, and a
  neutral **"Back to full targets"** snackbar. A Perfect Day or level-up
  that follows is celebrated as usual.
- Repeated taps are safe at three levels: the screen ignores a second
  request while a dialog or save is in flight, the controller's serial
  queue orders actions, and the domain operation is idempotent.
- The Minimum Day sheet no longer says "cannot be undone"; it says you can
  return to full targets any time today.

## 2. Achievements: today's unlocks are provisional

### Before

Unlocks were additive. If you undid the only thing that earned an
achievement today, the unlock stayed.

### Rule

Past achievement history is immutable. Unlocks dated today are provisional
until today is over. `AchievementRepository.reconcileUnlocks` (replacing
`unlockNew`) runs in one transaction:

1. Derive the full currently-earned set (`AchievementRules.evaluate`, which
   already describes the whole history).
2. Keep every stored unlock whose `unlocked_on` is not today.
3. For unlocks dated today: keep the ones whose key is still earned; delete
   the ones whose key isn't.
4. Insert every earned key that isn't stored.

Rows with keys this version doesn't know are never touched, whatever their
date. Running it again with the same history changes nothing. The question
asked is always "does the stored history currently earn this?", for every
achievement type. No achievement id is special-cased.

What can be removed: only an unlock whose `unlocked_on` is today, whose
key is known, and which today's history no longer earns. Examples are First
Rep after undoing the only completion; First Perfect, Perfect 3/10 or a
level after undoing today's Perfect Day or XP; Still Moving or Adaptable
after returning to full targets; and a streak threshold reached today.
Reflection achievements follow the same rule, though a reflection can't be
deleted today.

What can never be removed: any unlock dated before today, any unknown key,
and any unlock that is still earned.

`AchievementService.reconcile()` still returns only the newly stored
unlocks, for the celebration flow. `sync()` returns both lists. The UI's
`AchievementSync` uses it to refresh the board when an unlock disappears,
and nothing is celebrated for a removal. An unlock removed and earned
again for the same date (undo, then redo) is stored again exactly once and
is not celebrated a second time in that app session, which keeps the Phase
3 "celebrated once" behaviour.

Failure model: unchanged. A `PersistenceFailure` propagates from the
service; the UI reports and swallows it (achievements are secondary), and
the next run heals. A failed run writes nothing.

No schema change: the existing `achievement_unlocks` table already stores
session, key, `unlocked_on` and `unlocked_at`. There's no "provisional"
column and no startup rewrite beyond this current-day rule, which runs
where reconciliation always ran (Today load/refresh, after actions, Journey
refresh).

## 3. Sleep Before: semantics unchanged, clearer UX

The rule is locked and unchanged. For challenge date D, Sleep Before
records the bedtime of the sleep that ended on the morning of D. Sunday
23:10 to bed and Monday morning awake means Monday's check-in is 23:10.
Yesterday stays read-only, and there's no grace period.

The copy is keyed on the built-in id `sleep_before` (`isBedtimeCheckIn`),
not the `sleep` icon, which custom habits can also use. A renamed
`sleep_before` keeps both its new name and this copy. A custom clock-time
habit keeps neutral wording ("Logged · 21:30"), even with the sleep icon.
Stored titles are never rewritten.

Today card (not logged):

```
Sleep Before Target                         (i)
Last night's bedtime
Goal · before 23:30
Tap to log it for today's check-in
```

Logged:

```
Sleep Before Target                         (i)
Last night's bedtime · 22:48
Goal · before 23:30
Goal met                       (or: After the goal)
```

- **(i)** is a 48 dp info button, "Why does this count for today?". It
  opens a dialog: "Your sleep ended this morning, so last night's bedtime
  belongs to today's check-in. Log it each morning after you wake up."
  (**Got it**). It never logs anything.
- Screen reader: the card reads "Sleep Before Target, last night's bedtime
  22:48, goal before 23:30, Goal met, counts toward today's check-in, …".
  The explanation is a custom action next to **Clear time**, because the
  card is one merged node.
- Picker title: "When did you go to bed last night?" (unchanged).
- Setup tile: "Morning check-in · counts toward the day you wake up".
- Template description: "Morning check-in: log when you went to sleep last
  night. It counts toward the day you wake up."

The id, `HabitType.timeBefore`, stored values, target calculation,
`NightTime` mapping and Minimum Day behaviour are unchanged.

## Compatibility locks

| | Result |
|---|---|
| Database schema | **v5 → v5**, no migration, `drift_schemas/` and `lib/core/database/` unchanged |
| Backup | export **2**; import **1 and 2**; unchanged. An explicit `normal` day mode round-trips (new test) |
| Existing v1.0.0 data | loads without transformation; Minimum Day rows and historical unlocks stay valid |
| `applicationId` / iOS bundle id | `com.nextrep.nextrep` / unchanged |
| `pubspec.yaml` version | `1.0.0+1` |
| `AchievementKey` ids, habit ids, XP amounts and keys | unchanged |
| Dependencies | none added (`pubspec.yaml` / `pubspec.lock` unchanged) |
| Android / iOS projects | unchanged; release permissions as v1.0.0 (no INTERNET) |
| Network, analytics, accounts, sync | none |

## Tests

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` | **635 / 635** (605 at v1.0.0) |
| Migrations (`migration_test`, `_v3`, `_v4`, `_v5`) | 39 / 39 |
| Backup (`backup_restore`, `backup_v2_restore`, `backup_format`, `backup_v2`) | 71 / 71 |
| Targeted suites (tracking, time-before, achievements ×4, day one, phases 3/4/6/7/10A) | 164 / 164 |
| `flutter build apk --debug` | PASS |

New and changed coverage:

- `test/domain/phase2_tracking_test.dart` ("returning to full targets"):
  restores full targets, keeps progress exactly, revokes and keeps the right
  habit XP, creates a Perfect Day with exactly one bonus, idempotent
  returns, toggling never duplicates XP, rolled-over, past and future dates
  rejected, completed arc read-only. The old "is one-way" test is now
  "habit actions never change the mode by themselves". The reversal itself
  is covered by the new group.
- `test/domain/time_before_test.dart`: returning keeps the clock target and
  the logged time.
- `test/domain/achievement_reconciliation_test.dart`: First Rep removed and
  re-earned once; kept while still justified; First Perfect removed; Still
  Moving removed after returning to full targets and re-earned once;
  streak 3, Perfect 3 and level 2 reached today removed while earlier
  unlocks stay; earlier-dated and unknown-key unlocks never removed;
  idempotence; a failed run changes nothing and the next run heals.
- `test/domain/achievement_service_test.dart`: the "persisted exactly once"
  test now asserts the new current-day contract.
- `test/features/phase10a_flow_test.dart`: snackbar Undo through the
  persisted transition; Undo after a rollover never changes yesterday;
  confirmation copy, Cancel, confirm; rapid taps give one dialog and one
  transition; 2× text; a past Minimum Day is read-only; Sleep Before copy,
  semantics and the explanation by touch and as a screen-reader action;
  custom clock-time habit wording; renamed title kept; 2× text; past
  bedtime read-only; setup copy.
- `test/features/phase3_flow_test.dart`: undo removes today's First Rep,
  redo stores it again without a second celebration.
- `test/features/phase6_flow_test.dart`,
  `test/features/phase7_accessibility_test.dart`: updated to the new Sleep
  Before copy and semantics.
- `test/data/backup_v2_restore_test.dart`: a returned Minimum Day (explicit
  `normal`) round-trips in format 2 beside a Minimum Day.

## Deferred

Not implemented in 10A:

- Shareable progress / goal / achievement cards, and broader motion work:
  **Phase 10B**.
- New habit templates and an expanded achievement catalog: **Phase 10C**.
- Water reminders, social-media usage monitoring: **v1.2 planning**.
- Scheduled / non-daily habits, networking, accounts, cloud sync,
  analytics: not planned.
- TalkBack manual qualification: still deferred (automated semantics
  tests cover the new controls).
