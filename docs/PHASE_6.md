# Phase 6 — Seasonal Arc & Habit Evolution

## Goals

Phase 5 protected the user's data. Phase 6 widens what an Arc can be and
what a habit can measure, without weakening history, backups, privacy or
offline use:

- an explicit, persisted **Arc kind**: the Rolling 92-Day Arc (unchanged)
  and the **Seasonal Winter Arc**, 1 October – 31 December
- **late joining** of a season, with neutral "before you joined" days
- **schema v5** (arc kind, participation start) and **backup format 2**,
  with format-1 backups still restorable
- a bundled **habit template catalogue**, **custom habits** during setup,
  and setup-only edit and delete (Habit Setup v2)
- a new **clock-time habit type** (`timeBefore`) and a real **Sleep Before
  Target** template
- still fully local: no backend, no account, no network

## Arc kinds

```dart
enum ArcKind { rolling92, seasonalWinter }   // persisted by name
```

Every session stores its kind. It is never inferred from dates: a rolling
arc started on 1 October is still a rolling arc.

`WinterArcRules.problemWith(session)` is the single definition of a valid
session, used before a start is persisted and by backup validation:

| | setup | active / completed |
|---|---|---|
| all kinds | end ≥ start; no participation date | participation date set |
| rolling | start/end provisional, end = start + 91 | participation = start; end = start + 91 |
| seasonal | 1 Oct – 31 Dec of one year | 1 Oct – 31 Dec; participation inside it |

At most one arc is unfinished (setup or active), whatever its kind.

### Rolling semantics (unchanged)

Day 1 is the day Start is pressed and Day 92 is start + 91. Participation
starts on Day 1, so every derived number (streaks, Perfect Days,
consistency, XP, achievements, Journey, Insights) is exactly what it was
before Phase 6. All 440 Phase 1–5 tests pass unchanged apart from the new
Arc-choice step in UI flows and a few label changes.

### Seasonal semantics

The Seasonal Winter Arc is the fixed window **1 October – 31 December**
(inclusive, 92 days) of the device's local calendar year. Season day
numbers always count from 1 October: 1 Oct = Day 1, 15 Oct = Day 15,
15 Nov = Day 46, 31 Dec = Day 92. Joining late never renumbers the season.

### Seasonal availability

`SeasonalWinterRules.availabilityOn(today)`:

| local date | phase | Seasonal Winter Arc |
|---|---|---|
| 1 Jan – 31 Aug | `closed` | preview only: "Preseason opens September 1"; setup is rejected (`seasonNotOpen`) |
| 1 – 30 Sep | `preseason` | setup allowed for 1 Oct – 31 Dec; Start unavailable |
| 1 Oct – 31 Dec | `inSeason` | setup and join the current season |

The Rolling arc is available all year.

### Preseason setup

A September setup is created with start 1 Oct, end 31 Dec and no
participation date. It holds the one-unfinished-arc slot and can be
cancelled. It never starts on its own at midnight: on or after 1 October
the user still presses **Join Seasonal Winter Arc**.

### Start rules (`ArcStartRules`)

- rolling: start = today, end = today + 91, participation = today
- seasonal before 1 Oct: rejected with `seasonNotStarted` (the domain
  checks this; the disabled button is only a convenience)
- seasonal 1 Oct – 31 Dec: start and end stay, participation = today
- seasonal after 31 Dec (a setup that outlived its season): rejected with
  `seasonEnded`. It is never moved to next year. Habit Setup explains it
  and offers **Cancel setup**, then the user chooses a new Arc.

### Late join and participation

`participationStartDate` is the first calendar date the user takes part
in. It is a calendar fact stored when the arc starts. It is never derived
from `startedAt`, which is an instant whose local date can change after a
time-zone move or a restore elsewhere.

The rule lives in one place on `WinterArcSession`:

- `participationStart`, `isParticipatingOn(date)`, `isBeforeJoining(date)`
- `participatingDatesThrough(today)` = participation start … min(today, end)
- `joinedLate`, `joinDayNumber`, `participationLengthInDays`

`ArcHistory.elapsedDates` is now the participating dates that have
started. Days before joining are **neutral**. They are not missed or
partial days, not streak breaks, not consistency or habit denominators,
not reflection days, and they can never be Perfect or Minimum Days or earn
XP. Writes (habit actions, Minimum Day, reflections) need a participating
date, so even a clock moved back across the join date can't write one.

Example: joined 15 Oct, so participation runs 15 Oct – 31 Dec (78 days).
On 15 Oct the user is on **Day 15 of 92**, not "Day 1 of 78".

### Close-out

A seasonal arc stays active through all of 31 December. From the first
local date after it (1 January) the existing lifecycle reconciliation
completes it. A late join never closes early.

## Journey, scene and summary

- **Journey** still shows all 92 season days. Days before joining are a
  new state, `JourneyDayState.notJoined`, distinct from `future` and
  `missed`. The marker is small, muted and hollow with a **dashed**
  outline and no failure icon. Its screen-reader label is "Day 8. Before
  you joined this Seasonal Winter Arc." Tapping it shows a read-only note:
  "You joined on Day 15. Earlier season days are not counted against you."
  The header says "Joined on Day 15". The legend only shows the state for
  an arc that has such days.
- **Winter scene** progress follows the season day (from `startDate`), so
  joining on Day 45 shows the Day-45 world, not the trailhead.
- **Summary** of a completed seasonal arc: "SEASONAL WINTER ARC
  COMPLETE · 92-day season · 1 Oct – 31 Dec 2026 · Joined Day 15 · 78 days
  participated", then the usual metrics. Consistency is full days ÷
  **participated** days. Rolling summaries are unchanged.
- **Arc History** cards read "ROLLING WINTER ARC" or "SEASONAL WINTER
  ARC · 2026", plus "Joined Day 15" when it applies. **Today** shows
  "Seasonal Winter Arc · joined Day 15" under the date.

## Achievements

All achievements derive from participating history, so nothing is earned
on a day before joining.

- **Midwinter** is earned on season Day 46 itself, and only if that date
  is a participated date that has started. Joining after Day 46 leaves it
  locked for that arc; it is never awarded retroactively.
- **Summit**: a seasonal arc that stays active through 31 December and
  completes normally earns Summit **even if it was joined late**. It
  rewards finishing the season the user joined.

## Schema v5

`winter_arc_sessions` gains two columns (both appended):

| column | type | meaning |
|---|---|---|
| `arc_kind` | text, not null, default `'rolling92'` | `ArcKind` name |
| `participation_start_date` | text (ISO date), nullable | first participating date; null in setup |

### Migration v4 → v5 (`_from4To5`)

1. add `arc_kind` (every existing row reads `rolling92`, the only kind
   before Phase 6)
2. add `participation_start_date`
3. `UPDATE … SET participation_start_date = start_date WHERE status IN
   ('active', 'completed')`; sessions in setup stay null
4. no other table is touched

Snapshots: `drift_schemas/drift_schema_v5.json` was added; v1–v4 are
byte-for-byte unchanged. Tests cover empty v4 → v5 (validated against the
snapshot), populated v4 → v5 (every row of every table compared), v3 → v5,
v1 → v5 (empty and populated), and a setup session that migrates and then
starts. A further test checks that participation comes from `start_date`
even when `started_at` falls on another UTC date.

## Backup format 2

Exports now write `formatVersion: 2`. Each arc gains:

```json
{"id": 2, "kind": "seasonalWinter", "participationStartDate": "2026-10-15",
 "status": "active", "startDate": "2026-10-01", "endDate": "2026-12-31", …}
```

`participationStartDate` is null for an arc in setup. Habit `type` may
now be `timeBefore`. Everything else is as in format 1, including the
checksum model: SHA-256 over the canonical body. That still only detects
damage. It is **not** encryption, authentication or a signature.

### Version dispatch and format-1 compatibility

`BackupCodec.decode` reads `formatVersion` first:

- `1` → the frozen format-1 layout (Phase 5 fields only, habit types
  binary/count/duration)
- `2` → the format-2 layout (adds `kind`, `participationStartDate`,
  `timeBefore`)
- anything else (0, 3+, …) → `unsupportedVersion`, before anything else
  is read

The checksum is verified over the file **as written, in its own format**,
before any field is read or converted. A format-1 file is then checked by
format-1 rules. Format-2 fields in a format-1 file are rejected as unknown
fields, so v1 is never treated as a malformed v2. Only then is each arc
turned into the current model: `rolling92`, with participation = start
date if started, null in setup. Both formats produce the same
`BackupDocument`.

Compatibility is tested against a **frozen Phase 5 backup**,
`test/fixtures/phase5_backup_v1.nextrep`. It was written by the
unmodified Phase 5 encoder from synthetic data, before any codec change.
It is not a v2 file with its version changed.

### Validation additions

- kind invariants via `WinterArcRules.problemWith` (rolling 92 days and
  joined on the start; seasonal 1 Oct – 31 Dec of one year and joined
  inside it; no participation in setup)
- every dated record (progress, modes, XP, unlocks, reflections,
  revisions) must fall on a **participating** date
- a preseason seasonal setup may start after the export date
- at most 12 habits per arc
- `timeBefore`: target and every revision in the night window with
  minimum = target; progress is 0 (not logged) or a night time; and
  `completed` must agree with the recorded time and the target **in
  effect on that date** (with that date's revisions and mode, never
  today's target)

### Restore regression

Unchanged guarantees: size limit, full validation first, one-transaction
replace with rollback and a post-write verification, no merge, restored
arc ids shifted past every id the device has used, app reload after
restore, reminders off and pending reminders cancelled, no file contents
or reflection text in errors or logs. These are re-tested with format-2
seasonal, custom and clock-time data, and with the format-1 fixture.

## Habit evolution

### Template catalogue

`HabitTemplateCatalog` (in code, never stored or downloaded):

| id | title | type | goal / minimum |
|---|---|---|---|
| `workout` | Workout | minutes | 30 / 10 |
| `water` | Water Intake | count | 8 / 3 glasses |
| `learning` | Learning / Skills | minutes | 20 / 5 |
| `english` | English Practice | minutes | 10 / 5 |
| `no_junk_food` | No Junk Food | done / not done | — |
| `sleep_before` | Sleep Before Target | before a time | before 23:30, same on Minimum Days |
| `meditation` | Meditation | minutes | 10 / 5 |
| `journal` | Journal | done / not done | — |

Existing stable ids are reused. A fresh setup seeds the starter templates
(the first seven), with Workout, Water, Learning and No Junk Food on.

### Legacy sleep habit

Phases 1–5 had `sleep_on_time`, a done / not-done "Sleep Before Target".
It is **not migrated**: earlier arcs keep it as it was, and Reuse Last
Setup copies it as it is (still binary). The new template uses a new id,
`sleep_before`, because one id must never mean two types across arcs
(Insights group habits by id). To switch, remove the old habit in setup
and add the template. A new name can't duplicate an existing one, so the
old habit has to go first.

### Custom habits (setup only)

Created from **Add Habit → Create your own**. Types:

- done / not done: name and icon; target 1
- count: name, goal, Minimum Day goal, unit (default "times"), icon
- minutes: name, goal, Minimum Day goal, icon
- before a time: name, goal time, icon; Minimum Day target = goal

`SetupHabitRules` validates everything in the domain. The form only
mirrors it, and it resets numbers when the type changes, so nothing stale
is kept.

- **Ids**: `custom_` followed by 32 lowercase hex digits (128 bits) from
  `Random.secure()`, via an injectable `HabitIdGenerator`. Ids are never
  derived from the title, so renaming keeps the identity. They are
  portable through backups, and Insights aggregate a reused custom habit
  across arcs.
- **Names**: trimmed, 1–40 characters. Names that are the same apart from
  case and spacing (" reading " vs "Reading") are rejected within one arc.
  A template whose id is already present is rejected.
- **Limit**: 12 habits per arc, enforced in the domain
  (`habitLimitReached`), in backup validation, and shown in the UI (Add
  Habit disabled, with the reason).
- **Setup only**: while the arc is in setup, habits can be added, edited
  (the baseline is rewritten directly, **no revisions**) and deleted. Each
  repository write re-checks inside its transaction that the arc is still
  in setup. A running arc can't add or delete habits (`sessionNotInSetup`);
  renames, next-day goal edits and on/off work as before. A setup may hold
  zero habits for a moment, but Start needs at least one enabled.
- **Reuse Last Setup** copies custom and clock-time habits (final
  effective configuration) and nothing else. The Arc kind is chosen
  separately: a seasonal arc's habits can start a rolling arc and the
  other way round.

### Clock-time habits (`timeBefore`)

"Record the time this happened. It counts if that time is at or before
the target."

**`NightTime`** is a pure value type. It normalizes the supported night
window, **18:00 – 05:59**, to minutes on one evening's scale:

| 18:00 | 23:59 | 00:00 | 01:00 | 05:59 |
|---|---|---|---|---|
| 1080 | 1439 | 1440 | 1500 | 1799 |

Times after midnight sort after the evening, so the rule is plain
`actual <= target`. For a 01:00 target, 00:30 (1470) passes and 01:20
(1520) fails. For a 23:30 target, 00:10 (1450) fails. Midnight is 1440,
never 0, so a stored **0 means "not logged"**. Daytime values are
rejected everywhere.

**Storage**: the existing progress row. `currentValue` holds the
normalized time and `completed` is
`HabitType.isCompletedBy(value, effective target)`. That single rule
covers all four types and is applied by `DayRules`, so completion, habit
XP and the Perfect Day bonus reconcile through the existing persisted
transition path: never from the UI, and idempotently.

**Actions**: `setTime(time)` and `clearTime`. Increment, decrement,
complete and undo are rejected for this type, and `setTime` is rejected
for other types (`actionNotSupportedForHabitType`).

**Behaviour**:

- logged 00:45 against 01:00 → complete, +15 XP
- the same time again → no change
- changed to 01:15 → incomplete; the habit XP is revoked, and the Perfect
  Day bonus too if the day was perfect
- back to 00:45 → re-awarded once
- a late time stays stored ("After the goal"); it is real data, just not
  a completion
- clear → not logged; the snack bar's Undo restores the previous time

**Sleep Before Target semantics: a morning check-in.** The record on
challenge date D is the bedtime of the sleep that **ended on the morning
of D**. On 6 October the user logs "00:45", meaning they went to bed at
00:45 last night. So there is no writing to yesterday, no midnight grace
period, no past-day edit and no Day-93 extension. The card says "Last
night · 00:45 / Goal · before 01:00", and the picker asks "When did you go
to bed last night?". Other clock-time habits read "Logged · …".

**Minimum Day**: clock-time habits keep the same target. Their minimum
equals the target, set automatically, and the Minimum Day control is
hidden ("Clock-time habits keep the same target on a Minimum Day"). A
completed clock-time habit on a Minimum Day still earns habit XP, counts
for its streak and helps complete the Minimum Day. As always, a Minimum
Day is never a Perfect Day. A looser clock target for hard days needs its
own policy and is left for later.

**Target edits** after the start follow Phase 3: they take effect from
the next challenge day, past days keep their target, and on the last day
only renames are possible.

**Insights** stay completion-based. A day is applicable when the habit is
enabled; it is complete when the logged time met that day's target. A
time logged but late counts as applicable and not complete. There are no
bedtime averages yet.

## New Arc flow v2 and Habit Setup v2

```
first launch:   Onboarding → Choose your Arc → Habit Setup → Start / Join
after an arc:   Start New Arc → Choose Arc → Reuse last setup | Start fresh
                → Habit Setup → Start / Join
```

- **Choose your Arc**: "Rolling 92-Day Arc: Start whenever you're ready.
  92 days from the day you begin." and "Seasonal Winter Arc: October 1 –
  December 31. Join the season already in progress.", with a status line:
  "Preseason opens September 1" (card disabled), "Preseason · the season
  starts October 1" or "In season · 2026". Onboarding no longer creates
  anything; the arc is created only when a kind (and baseline) is chosen.
- **Habit Setup v2**: a "YOUR WINTER ARC" header with the kind, dates and
  season status ("The season is on Day 15 of 92. Join now and start on Day
  15; earlier days won't count against you."), then "YOUR HABITS" with an
  on/off switch per habit and an options menu (Edit, Remove), and an **Add
  Habit** button. That opens a sheet of template cards (type, goal,
  Minimum Day goal, or "Added") followed by **Create your own**. The bottom
  bar holds Start Winter Arc / Join Seasonal Winter Arc (disabled with a
  reason before 1 Oct or after the season) and Cancel setup.

## Insights

Insights use participating dates throughout. Days before a late join
count as neither elapsed, applicable nor reflection days, and an active
season's future days are excluded. Weighted consistency stays
Σ full participating days ÷ Σ elapsed participating days, across rolling
and seasonal arcs. "Day N now" is the active arc's own (season) day
number. Habits are still grouped by stable id, so custom ids aggregate
across arcs, two custom ids with the same title stay apart, and renames
keep their lineage. Setup sessions are excluded.

## Accessibility

Semantics were added for:

- the Rolling / Seasonal choice, including its availability text
- the joined-late explanation (Habit Setup header, Journey header, Today)
- `notJoined` markers ("Day 8. Before you joined this Seasonal Winter
  Arc.") and their read-only note
- Add Habit, including "unavailable: 12 habits is the limit"
- template cards (type, goals, "already added")
- the habit type chips, goal steppers, goal-time row and icon choices
- the clock card ("Sleep Before Target, Last night 00:45, goal before
  01:00, Done", with a hint to log or change)
- per-habit options (Edit, Remove)

States never rely on colour alone: dashed versus solid outlines, icons
and text. Widget tests run the setup screen, the Add Habit sheet and the
clock card at 2× text with no overflow. Reduced motion and the existing
scene behaviour are unchanged.

## Privacy and permissions

Nothing new leaves the device. Templates are code, ids are generated
locally, and there's no network, analytics, remote config, accounts or
health APIs. Habit names are user text, so setup writes that store them
use the private persistence guard (errors keep only the error type) and
bound parameters, never interpolated SQL. No new dependencies or
permissions.

## Tests

New suites:

| suite | file | tests |
|---|---|---|
| v4 → v5 migrations | `test/data/migration_v5_test.dart` | 11 |
| seasonal lifecycle and rolling regression | `test/domain/seasonal_arc_test.dart` | 22 |
| participation, Journey, achievements, Insights | `test/domain/participation_test.dart` | 20 |
| NightTime and clock-time tracking | `test/domain/time_before_test.dart` | 17 |
| templates, custom and setup habits, reuse | `test/domain/setup_habits_test.dart` | 16 |
| backup format 2 and format-1 compatibility | `test/domain/backup_v2_test.dart` | 15 |
| format-2 / format-1 restore | `test/data/backup_v2_restore_test.dart` | 10 |
| Phase 6 UI flows | `test/features/phase6_flow_test.dart` | 15 |
| Phase 6 device smoke | `integration_test/phase6_smoke_test.dart` | 1 |

The older populated migration chains now migrate through to v5. UI flows
pick "Rolling 92-Day Arc" after "Let's Begin".

## Validation

Run on 2026-10-04/05 from the final branch code unless noted.

| check | result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` | **566 / 566** |
| `flutter test --coverage` | 93.3% of handwritten `lib` (generated code excluded) |
| migration tests (v1 → … → v5) | 39 / 39 |
| backup tests (format 1 + 2, restore) | 70 / 70 |
| `dart run build_runner build --delete-conflicting-outputs` | regenerated; `drift_schema_v5.json` added, v1–v4 unchanged |
| `flutter build apk --debug` / `--release` | pass |
| `flutter build ios --simulator` | pass |
| integration tests, emulator-5554 (API 36) | 6 / 6 |
| integration tests, CPH2707 (Android 16, physical) | 6 / 6 (see below) |
| integration tests, iPhone 17 simulator (iOS 27) | 6 / 6 |

On CPH2707 the first full run passed five suites. The Phase 2 suite
"did not complete" (wireless ADB), so Phase 5 didn't run. Phase 2, 5
and 6 were then re-run one by one on the final code and passed.

### Release APK permissions (`aapt2 dump permissions`)

`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, plus the
app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. That is the same
as Phase 5:

| permission | |
|---|---|
| `android.permission.INTERNET` | ABSENT |
| `android.permission.SCHEDULE_EXACT_ALARM` | ABSENT |
| `android.permission.USE_EXACT_ALARM` | ABSENT |
| `android.permission.MANAGE_EXTERNAL_STORAGE` | ABSENT |
| `android.permission.READ_EXTERNAL_STORAGE` | ABSENT |
| `android.permission.WRITE_EXTERNAL_STORAGE` | ABSENT |

### Emulator (API 36, release build, device clock untouched)

The real date (4 October) is in season, so the late-join path was
exercised without changing any clock:

- Let's Begin → Choose your Arc ("In season · 2026") → Seasonal
- Habit Setup header: "The season is on Day 4 of 92 …"
- habit options, the Add Habit template sheet ("Added" states), the
  custom form, and Sleep Before Target switched on
- Join → Today "Day 4 of 92 · Seasonal Winter Arc · joined Day 4"
- the Android time picker ("When did you go to bed last night?"):
  - 10:30 PM → "Last night · 22:30", +15 XP, Undo, First Rep unlocked
  - 10:30 AM → refused ("Pick a time between 18:00 and 05:59.")
- Journey: Days 1–3 dashed and neutral, header "Joined on Day 4"
- after reinstalling the final build (data kept) and the date rolling
  over: Day 5, the trail lit only from Day 4, the chapter "0 of 11 full
  days", Day 2's read-only "Before you joined" note

Preseason, closed months, 1 Oct / 31 Dec / 1 Jan transitions, Summary
labels and backup v1/v2 restores were validated through the
injected-clock widget and integration tests, not by changing the system
date. The Phase 6 smoke test also ran export → change → restore of a
format-2 file on all three targets.

### Physical Android (CPH2707, Android 16)

- integration tests 6 / 6, including the Phase 6 smoke test: seasonal
  late join, template, custom count habit, the time picker, restart,
  format-2 export/restore and Insights
- the release build was installed over the Phase 5 install **with its
  data kept**. That is a real v4 → v5 migration: the running arc came back
  as a rolling arc on Day 2 with 75 XP, its streaks and 3/15
  achievements, and Arc History labels it "ROLLING WINTER ARC"
- the app was left installed with that data; no settings were changed

### iOS

`flutter build ios --simulator` and integration 6 / 6 on the iPhone 17
simulator, including the Phase 6 smoke test (time picker, setup, the
seasonal Journey, the format-2 codec through the in-memory file adapter).
**PHYSICAL iOS — MANUAL REQUIRED**: no iPhone was connected, so the
document picker, notifications and the time picker on a device are
untested.


## Limitations

- Only the fixed Winter season (1 Oct – 31 Dec). There are no custom
  seasons or lengths.
- Habits can't be added to or deleted from a running arc; that needs a
  dated "exists from" model. Switch one off instead.
- Clock-time habits support only 18:00 – 05:59 and keep the same target on
  Minimum Days. There are no bedtime analytics.
- A seasonal setup that outlives its season must be cancelled by hand.
  It's never converted to the next year.
- The legacy binary sleep habit isn't converted (by design).
- Backups are still unencrypted, and restore is still full-replace only.

## Phase 7 handoff

Recommended next:

- active-arc habit creation with a dated existence model (and deletion as
  "ended from")
- a Minimum Day policy for clock-time habits (e.g. a separate lenient
  time), and bedtime trends in Insights
- more clock-time templates (Phone Off Before, Start Reading Before) once
  the policy exists
- an iOS device pass (document picker, notifications, time picker) and a
  TalkBack / VoiceOver audit
- optional encrypted backup as format 3; the version dispatch is ready
- restrained Journey parallax and chapter-specific seasonal atmosphere
  (deferred from Phase 6 polish)
