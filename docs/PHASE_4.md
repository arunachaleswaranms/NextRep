# Phase 4 — Retention & Life After the Summit

## Goals

Phase 3 ended at the summit: a completed arc became a read-only summary,
with nothing after it. Phase 4 answers "what happens after my first Winter
Arc, and what brings me back tomorrow?":

- start another arc after finishing one (reuse the last setup or start fresh)
- keep every arc, browse past arcs in Arc History, read-only and scoped to
  that arc
- a lightweight nightly reflection: the Journal
- opt-in local reminders (a daily nudge and an evening reflection prompt)
  that deep-link into the app
- five more achievements, two of them for reflecting
- schema v4 with a tested migration chain

Still out of scope: accounts, sync, a backend, analytics, telemetry and AI.
Everything stays on the device.

## Multiple-session model

The database could always hold several `winter_arc_sessions` rows. Phase 4
makes that a product feature, with one invariant:

> **At most one unfinished arc** (status `setup` or `active`). Any number
> of `completed` arcs.

It is enforced three times:

1. `WinterArcService` runs mutations through a `SerialQueue` and rejects
   `startNewArc` with `DomainRule.arcInProgress`.
2. `DriftWinterArcRepository.createSetupSession` checks inside its
   transaction and throws the same rule.
3. Schema v4 adds a partial unique index:
   `CREATE UNIQUE INDEX single_open_session ON winter_arc_sessions
   ((status IN ('setup','active'))) WHERE status IN ('setup','active')`.
   A second unfinished row can't be written, even by a bug.

### Current vs historical arc resolution

Before Phase 4, every service took "the latest session". With several arcs
that guess is wrong, so lookups are now explicit (`WinterArcRepository`):

| Method | Means |
|---|---|
| `currentSession()` | the unfinished arc (setup or active), or null |
| `latestCompletedSession()` | the newest completed arc, or null |
| `sessionById(id)` | exactly that arc |
| `listSessions()` | all arcs, newest first |
| `latestSession()` | newest of any status (kept for close-out tests; no screen uses it) |

`CurrentArcService` (`domain/winter_arc/current_arc_service.dart`) turns
these into the questions use cases ask:

- `resolve()` returns an `ArcResolution {current, latestCompleted}`, with
  `active`, `setup` and `home`.
- `home` is the arc the app's home shows: the active arc or, with nothing
  unfinished, the latest completed arc. It is null while a new arc is in
  setup.
- `requireHome()` is used by Today, Journey, Journal, the Habits screen
  and the current-arc achievements. It keeps Phase 3's behaviour of showing
  a just-completed arc read-only until the router moves on.
- `requireStarted(id)` is used by history views: that arc, as long as it
  has started.
- `requireWritable(sessionId:)` is used by every write. Only the active
  arc can be written. If the arc the user was looking at has since closed,
  the write is rejected with `arcCompleted`, never redirected to a
  different arc. Today, Habits and the Journal pass the session id they
  are showing.

`ArcLifecycleService.reconcile()` only ever examines the current arc, so a
completed arc is never written again. `resolve()` runs the close-out and
then resolves. `arcResolutionProvider` (it replaces Phase 3's
`arcStatusProvider`) publishes the result and drives the router.

## New Arc flow

The summary of the latest completed arc offers **Start New Arc** as its
primary action, only while nothing is in setup or running. It opens
`/new-arc`:

- **Reuse last setup** shows a preview of the habits it will start with.
- **Start fresh** uses the starter habits.

Either choice calls `WinterArcService.startNewArc(baseline)`, which creates
a *setup* session. The router then moves to Habit Setup, and the start date
stays provisional until **Start Winter Arc**, exactly like the first time.
Returning users never see first-time onboarding again: it is redirected
away once any arc exists.

### Start Fresh semantics

`StarterHabits.seed(now)`: the same catalogue, targets, minimums and
default on/off as a first install.

### Reuse Last Setup semantics

For each habit of the latest completed arc, the new baseline is its
**final effective configuration**: `HabitHistory.configOn(habit, endDate)`.
That is the revision in effect on the last day, not the original baseline.

| Copied | Not copied |
|---|---|
| id, current title, type, unit, icon, sort order | progress, XP, streaks |
| target, minimum target, enabled (as of the last day) | Perfect / Minimum Days, day modes |
| | revisions, achievements, reflections |

Old revisions stay with the old arc. Creating the new arc writes nothing to
the completed one. A test compares every row of Arc 1 (session, habits,
revisions, progress, modes, XP, unlocks, reflections) before and after
Arc 2 is created, started, tracked and reflected on.

## Session isolation

Every per-arc table is keyed by `session_id`, and every read passes the id
explicitly:

| Data | Scoping |
|---|---|
| habits, revisions, progress, modes, XP | `ProgressRepository.loadArc(id)`, `HabitRepository.historyForSession(id)` |
| achievements | `AchievementService.boardFor(id)`; `reconcile()` only the home arc |
| reflections | `ReflectionService.journalFor(id)`, `ReflectionRepository.*(sessionId)` |
| Journey, summary | `HabitTrackingService.journeyFor(id)` / `historyFor(id)` |
| Arc History cards | `ArcHistoryService.card(id)` |

`multi_arc_test.dart` builds Arc A and Arc B with different habits, goals,
progress, modes, achievements and moods, and checks that no value leaks
either way.

## Arc History

`ArcHistoryService` (`domain/history/`):

- `sessions()` returns started arcs, newest first. A setup arc isn't
  history yet.
- `card(id)` returns `ArcHistoryCard {session, summary: ArcSummary,
  reflectionCount}`. `ArcSummary` is the Phase 3 summary, so a card and its
  summary always agree.

The list only reads session rows. Each card loads its own numbers through
`arcHistoryCardProvider(id)` inside a lazy `SliverList.builder`, so only
visible cards do any work. No cache was added: arcs are few and
correctness comes first.

A card shows the dates (`arcDateRange`, with both years when an arc spans
two), an ACTIVE or COMPLETED chip (icon and text, not colour alone), level
and XP, Perfect Days, consistency, best Perfect streak, achievements and
reflections. The whole card is one semantics node with a full spoken
summary.

### Navigation

- Active shell: **Today · Journey · Journal · History**. Achievements stay
  behind the trophy. There is no Profile tab.
- With no arc running, the summary links to **Arc History** (`/arcs`, the
  same list as a full-screen page).
- Tapping the active arc's card goes to Today. A completed arc opens its
  overview.

### Historical routing

Every history route carries the arc id and reloads that arc from storage.
No domain object travels in route `extra`.

| Route | Screen |
|---|---|
| `/arc/:sessionId` | `SummaryScreen(sessionId)`, the overview; also the home of a completed arc |
| `/arc/:sessionId/journey` | `JourneyScreen(sessionId)`, read-only, with a "Winter Arc · dates" header |
| `/arc/:sessionId/journal` | `JournalScreen(sessionId)`, read-only |
| `/arc/:sessionId/achievements` | `AchievementsScreen(sessionId)`, read-only |

History views never write: no close-out, no achievement reconcile, no
celebration. The one exception is the home summary of the arc that just
completed. It reconciles first so its Summit (and any v2 unlock that its
history earned) is stored, as in Phase 3.

### Redirect rules (`AppRoutes.redirect`)

- Active-arc screens (tabs, `/achievements`) need an active arc; otherwise
  they go home.
- Onboarding, setup and New Arc are closed while an arc runs.
- The current arc is never shown as history: `/arc/<current id>` goes
  home.
- Onboarding is only for a first install; a malformed `/arc/x` goes home.

### Boot resolution (`AppRoutes.home`)

1. An arc in setup → Habit Setup
2. An active arc → Today
3. Otherwise, after any completed arc → that latest arc's summary
4. Nothing → first-time onboarding

Nothing is created automatically: the user chooses Start New Arc.

## Journal

### Model

`DailyReflection {sessionId, date, mood?, win?, improvement?, createdAt,
updatedAt}`. There's at most one per session and date, and the challenge
day number is derived, never stored.

- `Mood` is `rough | okay | good | excellent`, persisted by a stable `key`.
  An unknown stored key reads as "no mood". Labels and icons live in the UI
  (`MoodStyle`).
- A separate `note` field was not added; two one-line answers keep it at
  about 20 seconds.

### Validation (`ReflectionRules`)

- Answers are trimmed; whitespace only counts as empty.
- At most 240 characters each, counted as grapheme clusters (an emoji
  counts once, like the text field's counter).
- A mood or at least one answer is required. An empty reflection is
  rejected (`reflectionEmpty`) and announced in a live region.
- Answers are one line: Enter submits or moves on, and pasted line breaks
  become spaces.

### Edit rules (`ReflectionService.save`)

| Arc / date | |
|---|---|
| active arc, today | writable; a second save updates (creation time kept) |
| active arc, earlier date | read-only (`reflectionReadOnly`) |
| future date / outside the arc | `reflectionNotAvailable` |
| completed arc | read-only (`arcCompleted`) |

### UI

- **Journal tab:** "TODAY · DAY n" with the editor: four mood buttons
  (icon and label, a mutually exclusive group, 2×2 at large text), "One win
  today", "One thing to improve", Save. A saved reflection shows as an
  entry with Edit.
- **PAST** lists reflections newest first (lazy). Missing days are simply
  absent, and the copy is "Skipping a night is fine."
- **Historical Journal:** the same entries, no editor.
- After a save, achievements are reconciled best effort. A failure never
  undoes the reflection.

## Schema v4 and migrations

`schemaVersion = 4`. Snapshot `drift_schemas/drift_schema_v4.json`; v1–v3
are unchanged.

| Table | Columns | Keys |
|---|---|---|
| `daily_reflections` | session_id, date, mood (nullable key), win, improvement (nullable), created_at, updated_at | PK (session_id, date); FK session → cascade |
| `reminder_preferences` | id (CHECK = 1), daily_enabled, daily_hour, daily_minute, reflection_enabled, reflection_hour, reflection_minute, updated_at | PK id; hour/minute CHECKs |
| index `single_open_session` | partial unique index on unfinished sessions | |

Reminder preferences are a Drift singleton row rather than
`shared_preferences`: one database and one migration story, and no extra
dependency for a few values. No row means the defaults (both off).

`_from3To4` is additive: two empty tables and the index, with no row
rewritten. Phase 1–3 only ever created one session, so the index can't
conflict with existing data.

Migration tests (28 in total):

- **v3 → v4** (`migration_v4_test.dart`): empty v3 to the exact v4 schema;
  empty v2 → v3 → v4.
- **Realistic v3 → v4:** a *completed* Phase 3 arc with a renamed habit,
  next-day revisions, a Minimum Day, a Perfect Day bonus and 5 unlocks. The
  session and status, habits, minimums, revisions, modes, progress, XP and
  bonuses, unlocks, Journey states, and a no-duplicate reconcile are all
  checked. Then: empty reflections, default reminders, a reused new arc
  started, a reflection saved and `first_reflection` unlocked, with Arc 1
  untouched.
- **v2 → v3 → v4** (`migration_v3_test.dart`) and **v1 → v2 → v3 → v4**
  (`migration_test.dart`): the Phase 2/3 fixtures now run the whole chain
  and validate against v4. All their assertions are kept, plus a reflection
  write after migration.
- **Device:** a Phase 3 build with real data (15 XP, First Rep, water 3/8)
  was upgraded in place to Phase 4 on the emulator. Everything was intact,
  and achievements show 1/15.

## Reminders

### Architecture

```
ReminderPreferences (Drift row)        WinterArcRepository
             \                          /
        ReminderService.reconcile()  (serialised, idempotent)
             |  ReminderPlanner.plan(prefs, active arc, now)   ← pure
             v
     ReminderScheduler  (interface)
       ├─ LocalNotificationScheduler   (flutter_local_notifications)
       ├─ DisabledReminderScheduler    (default outside main.dart)
       └─ FakeReminderScheduler        (tests)
```

- **Planner:** one one-shot notification per enabled kind and arc day,
  from now up to `horizonDays = 14` ahead, at the local wall-clock time
  (`DateTime(y, m, d, h, min)`, so DST is applied per date).
  - Nothing is planned without an active arc, for a setup or completed
    arc, past the arc's last day, or in the past.
  - Copy is generic and names the day: "Winter Arc · Day 12 / Your Winter
    Arc is waiting.", "How did today go? / Take 20 seconds to reflect on
    Day 12."
  - Reflection text is never in a notification.
- **Why one-shot and not an OS daily repeat:** reminders stop on their own
  at the end of the arc and survive time-zone changes (re-planned on the
  next reconcile). If the app isn't opened for two weeks they pause instead
  of nagging.
- **Reconcile runs** at launch, on resume (`_RoutedApp`), whenever the
  active arc's id changes (start, close-out, new arc) and after every
  preference change. An empty plan cancels everything pending.
- **Scheduling:** `zonedSchedule` with
  `AndroidScheduleMode.inexactAllowWhileIdle`. Each instant goes as a UTC
  `TZDateTime`, so it is exact without the device's time-zone name (no
  `flutter_timezone` plugin needed). Android may deliver up to a short
  window late, which suits a habit nudge. **No exact-alarm permission.**
- Two Android channels (`daily_reminder`, `reflection_reminder`), so each
  can be silenced in system settings. A white vector snowflake
  (`ic_stat_reminder`) is the small icon, kept from release resource
  shrinking by `res/raw/keep.xml`.

### Package choice

**`flutter_local_notifications` 22.3.1** (with `timezone` 0.11.1, which
it already depends on):

- a Flutter Favorite from a verified publisher (dexterx.dev)
- 150/160 pub points, about 3M downloads in 30 days, latest release
  13 Sep 2026
- supports AGP 9 built-in Kotlin and Swift Package Manager
- local only, no network

It needs core library desugaring (`desugar_jdk_libs` 2.1.4) and two
receivers in the manifest. `characters` is now a direct dependency (it was
already transitive) for grapheme-aware length checks.

### Settings and permissions

- **Reminders** (bell on Today and Journal, `/settings/reminders`): Daily
  reminder (on/off, time) and Evening reflection (on/off, time).
- Both are **off by default**. 08:00 and 21:00 are only the pickers'
  starting values.
- Permission is requested only when the user turns a reminder on. That is
  the Android 13+ runtime prompt, or the iOS alert/sound request.
- If denied, nothing is saved, the switch stays off and a message explains
  how to allow it later. The app never prompts on its own.
- If notifications are blocked later in system settings, the screen says
  so; it re-checks on resume.
- The Journal and every other feature work without permission.

### Deep links

The notification payload is the kind's stable payload (`today` /
`journal`). `AppRoutes.forReminder(payload, resolution)`:

- With an active arc: `today` → Today, `journal` → Journal (today's
  reflection).
- Otherwise it goes home: the completed arc's summary, Habit Setup or
  onboarding. A stale reminder can never open a writable Today.
- **Foreground and background taps:** a stream from
  `onDidReceiveNotificationResponse`. `_RoutedApp` runs the close-out
  first, then routes.
- **Cold launch:** `getNotificationAppLaunchDetails()` in `main.dart` →
  `reminderLaunchPayloadProvider` → `bootLocationProvider` (close-out
  first).

### Android permissions added by Phase 4

| Permission | From | Why |
|---|---|---|
| `POST_NOTIFICATIONS` | plugin manifest | Android 13+ runtime permission to show notifications |
| `VIBRATE` | plugin manifest | default notification vibration |
| `RECEIVE_BOOT_COMPLETED` | app manifest | the plugin's boot receiver reschedules pending reminders after a reboot or app update |

The release APK (`aapt2 dump permissions`) has **no `INTERNET`**, **no
`SCHEDULE_EXACT_ALARM`** and **no `USE_EXACT_ALARM`**. The existing
app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` is unchanged.

## Achievements: catalog v2

All 10 Phase 3 keys and their semantics are unchanged. Five were added (15
in total):

| Key | Title | Earned when | Earned on |
|---|---|---|---|
| `first_reflection` | Looking Inward | first saved reflection | its date |
| `reflections_7` | Seven Check-ins | reflections on 7 dates, not necessarily consecutive | the 7th date |
| `minimum_3` | Adaptable | 3 fully completed Minimum Days | the 3rd |
| `perfect_10` | Ten Clean Sweeps | 10 Perfect Days | the 10th |
| `level_5` | Stronger Every Day | running XP ≥ 1,000 | first date it was |

- **`AchievementContext {history, reflectionDates}`**: the caller loads
  reflection dates from storage. `AchievementRules.evaluate(context)`
  stays pure. Reflection dates outside the arc's elapsed days and
  duplicates are ignored.
- Reconciliation is unchanged in principle: idempotent, persisted once,
  never XP, outside every write transaction, self-healing.
- It now runs on the **home** arc only. After a reflection it runs best
  effort, and only newly stored unlocks are celebrated.
- Unlocks remain permanent.

## Accessibility

New semantics:

- mood buttons ("Mood: Good", selected, mutually exclusive group)
- Save Reflection, and the validation error (a live region)
- Journal entries: one node "Day 3, Sat 3 Oct. Mood: Good. Win: …"
- Edit ("Edit today's reflection")
- History cards: one node with the full summary
- reminder switches, and reminder time rows (their own node, "Daily
  reminder time, 8:00 AM")
- New Arc choices (with the habits they start with)

Found and fixed on the emulator: the time row originally merged with the
card and swallowed its switch for screen readers. A test now covers it.

Fixed after an independent code review:

- Reminder edits are now applied to the *stored* preferences inside the
  service's queue (`ReminderService.update(change)`). Before, two quick
  toggles could each send a stale snapshot and undo each other. A test
  covers concurrent edits.
- The active arc's History card now also re-reads when new achievements
  are stored.

Status and mood are never colour-only (icons and text). At 2× text a
widget test covers the Journal, History and New Arc; the mood row becomes
2×2 and Edit moves under the entry. Phase 3 reduced-motion behaviour is
unchanged.

## Privacy

- Reflections live only in the local SQLite database. No upload, analytics
  or telemetry.
- Reflection text is never logged. Database errors can quote bound values
  (`SqliteException.toString` includes parameters), so reflection storage
  uses `guardPrivatePersistence`, which keeps only the error's type. Domain
  failure messages never include text. A test closes the database
  mid-save and checks that the failure doesn't contain the text.
- Notifications contain only generic copy.

## Validation

| Check | Result |
|---|---|
| `dart format` / `flutter analyze` | clean / no issues |
| `flutter test` | **348 / 348** (Phase 3: 257) |
| `flutter test --coverage` | 93.0% of handwritten `lib/` (domain 95.8%, data 98.1%, features 94.6%, shared 95.7%) |
| migration tests (v1/v2/v3 → v4) | 28 / 28 |
| integration, Android emulator (API 36) | 4 / 4 (Day 1, Phase 2, Phase 3, new Phase 4 smoke) |
| integration, iOS simulator (iPhone 17, iOS 27) | 4 / 4 |
| `flutter build apk --debug` / `--release` | built |
| `flutter build ios --simulator` | built (Swift Package Manager; no CocoaPods needed) |
| release permission audit | as above: no INTERNET, no exact alarms |

New test files:

- `multi_arc_test`, `reflection_test`, `reminder_test`,
  `achievement_v2_test`, `arc_history_service_test`
- `app/app_routes_test`, `shared/arc_labels_test`
- `data/migration_v4_test`
- `features/phase4_flow_test`
- `integration_test/phase4_smoke_test`

Phase 1–3 tests changed only for deliberate changes:

- the catalog is now 15 (`/10` → `/15`)
- `AchievementRules.evaluate` takes a context
- migration fixtures run to v4
- one lifecycle helper reads a completed arc via `latestSession()`
  (`currentSession()` now means unfinished)
- the Phase 1 smoke test scrolls before tapping (needed on the shorter
  iPhone screen)

### Emulator: manual reminder validation (Android 16 / API 36)

| Step | Result |
|---|---|
| Phase 3 → Phase 4 in-place upgrade, data intact | PASS |
| Reminders off by default; turning one on shows the Android 13+ prompt | PASS |
| Alarms are inexact `RTC_WAKEUP` one-shots per day (dumpsys), no exact alarm | PASS |
| Evening reflection at now+3 min, app in background → delivered (11:53:36) | PASS |
| Tap (app in background) → Journal, today's reflection | PASS |
| Daily reminder, process killed → delivered (11:58:51); cold-launch tap → Today | PASS |
| Reflection reminder, process killed; cold-launch tap → Journal | PASS |
| Both off → 0 pending alarms | PASS |
| Permission denied → message, stays off, 0 alarms, app works | PASS |
| Release APK: reminder delivered with icon and channel (R8 safe) | PASS |
| Journal keyboard: field and Save stay visible; IME "done" saves | PASS |
| Arc completion cancels reminders | unit and widget tests only (needs a device date change) |

- **Physical Android:** MANUAL REQUIRED. No device was connected.
- **iOS:** the simulator build and all integration tests pass. Delivery of
  iOS notifications was not checked (permission prompt and delivery on the
  simulator are manual).

## Limitations

- Reminders are planned 14 days ahead; after two weeks without opening the
  app they pause until the next launch.
- Inexact delivery: a reminder may come a little after its time.
- Arc completion while the app sits untouched in the foreground still
  waits for the next entry point (Phase 3 behaviour).
- No deleting or editing past arcs or past reflections. No data export.
  A setup arc can't be cancelled; it can only be started.
- No `note` field; no historical reflection editing.
- Journey parallax and per-chapter scenery were not done: retention came
  first.

## Phase 5 handoff

1. A physical Android pass (haptics, TalkBack, notification delivery under
   Doze) and iOS notification delivery on a device.
2. Data safety before anything destructive: local export/backup of arcs
   and the Journal, then possibly deleting an arc or cancelling a setup.
3. A seasonal Winter Arc preset (1 Oct → 31 Dec) next to the rolling arc.
4. A gentle insight across arcs (compare Arc 1 vs Arc 2), mood trends from
   the Journal (on device, no AI).
5. Journey scene v2: restrained parallax and per-chapter art, with reduced
   motion respected.
6. Habit creation and a time-threshold habit type for "Sleep Before
   Target".
