# Phase 5 — Data Safety & Insight

## Goals

Phase 4 made NextRep something you keep using after the first arc. Phase 5
protects that history and turns it into on-device insight:

- a portable, versioned, checksummed backup file
- full validation before anything is changed
- a transactional full restore (replace, never merge)
- deleting a completed arc, and cancelling an arc still in setup
- Insights across arcs: consistency, habits, moods
- still fully offline: no backend, no account, no network

**Schema: still v4.** Every Phase 5 feature works from data that was
already stored, so no migration was added (see [Schema decision](#schema-decision)).

## Backup design

### File format

A backup is one UTF-8 JSON object in a file named
`nextrep-backup-YYYY-MM-DD.nextrep` (the name never contains user data):

```json
{
  "appVersion": "1.0.0",
  "checksum": {"algorithm": "sha256", "value": "<64 hex digits>"},
  "data": {
    "arcs": [
      {
        "id": 1, "status": "completed",
        "startDate": "2026-07-01", "endDate": "2026-09-30",
        "createdAt": "2026-07-01T08:00:00.000Z", "startedAt": "…",
        "habits": [{"id": "water", "title": "Water Intake", "type": "count",
                    "target": 8, "minimumTarget": 3, "unit": "glasses",
                    "icon": "water", "enabled": true, "sortOrder": 1,
                    "createdAt": "…"}],
        "habitRevisions": [{"habitId", "effectiveFrom", "target",
                            "minimumTarget", "enabled", "createdAt"}],
        "dayModes": [{"date", "mode", "changedAt"}],
        "progress": [{"habitId", "date", "value", "completed",
                      "completedAt", "updatedAt"}],
        "xp": [{"sourceKey", "reason", "amount", "habitId", "date",
                "createdAt"}],
        "achievements": [{"key", "earnedOn", "unlockedAt"}],
        "reflections": [{"date", "mood", "win", "improvement",
                         "createdAt", "updatedAt"}]
      }
    ],
    "reminders": {"dailyTime": "07:30", "reflectionTime": "21:15"}
  },
  "exportedAt": "2026-10-04T15:09:29.796Z",
  "formatVersion": 1,
  "product": "NextRep"
}
```

- **Domain names, not database names.** `habits`, `progress`, `xp`, `icon`,
  `value` rather than `daily_habit_progress_entries` or `current_value`. A
  test checks that no table or column name appears in the file.
- **Nested per arc.** A child record can't point at a missing arc: the
  file's structure ties each record to its arc.
- **Enum values** use their stable persisted names (`completed`, `count`,
  `minimum`, `habitCompleted`, mood keys, achievement ids), frozen for
  format 1.
- **Timestamps** are ISO-8601 UTC instants. They're read back into local
  time, as the app stores them. **Dates** are `YYYY-MM-DD` calendar dates.
- **Arc ids** only link records inside the file. See
  [Restore](#restore-semantics) for how they're assigned on import.

### formatVersion

`formatVersion` (now 1) describes the file layout. It's independent of the
database schema version (4): a later app can write format 2 without a schema
change, or change the schema and keep writing format 1. An unknown version
(2, 99, 0) is rejected outright with "made by a newer version of NextRep".
That happens before anything else is read, so a future format is never
partly interpreted.

### Checksum model

`checksum.value` is the SHA-256 (package `crypto`) of the canonical encoding
of every other top-level field. The canonical encoding:

- object keys sorted by UTF-16 code units at every level
- no extra whitespace
- strings escaped as `jsonEncode` does
- integers, strings, booleans and null only (no floating-point values)

Export writes the canonical form itself, so `decode → encode` reproduces the
file byte for byte. On import the checksum is recomputed from the parsed
data. A pretty-printed copy of a backup is still accepted, while any changed
value is rejected.

The checksum detects accidental damage: a truncated download, a flipped
byte, a careless edit. It is **not** encryption, authentication or a
signature. Anyone can edit a backup and recompute it. The file is plain,
unencrypted JSON, and the app says so.

### What is included

Everything authoritative, for every arc (setup, active and completed):

- **sessions:** id, status, dates, created/started time
- **habits:** baseline configuration, title, type, unit, icon, order,
  created time
- **revisions:** dated configuration changes
- **day modes:** Minimum Days
- **progress:** value, completion, completion and update times
- **XP ledger:** source key, reason, amount, habit, date, time
- **achievement unlocks:** key, earned date, unlock time
- **reflections:** mood, win, improvement, times
- **reminder times:** the times only, not whether reminders are on

### What is derived and not exported

Streaks, levels, Perfect Days, consistency, Journey states, arc summaries,
History cards and insights. They're recomputed from the records after a
restore, exactly as at launch. XP row ids (internal insertion counters) and
whether reminders are on are not exported either.

### Reflection privacy

A backup holds the user's Journal. Before every export, a dialog says:

> This backup contains your private NextRep history and reflections. Store
> it somewhere you trust.
>
> The file is not encrypted: anyone who can open it can read your Journal.

The Data & Backup screen repeats: "Backups are stored wherever you choose.
NextRep does not upload them." and that a backup is checksummed, not
encrypted. Nowhere is it called secure or encrypted.

Reflection text, backup contents and habit names never reach logs:

- Backup failures name a position and a rule (`arcs[1].progress[4]: date
  outside the arc`), never a value, and never a field name taken from the
  file.
- JSON parse errors (which quote their input) are not kept.
- Restore and delete errors go through `guardPrivatePersistence`, which
  keeps only the exception type, because SQLite quotes bound values.
- Tests check that no failure contains reflection text or habit names. On
  the emulator, logcat was checked after export, restore and a rejected
  file: none of the content appeared.
- The picked file is read from Android's private cache copy, which is
  cleared after reading.

### Export dependency choice

| Package | Android save | Android open | iOS save | iOS open | Notes |
|---|---|---|---|---|---|
| `file_selector` 1.1.0 (flutter.dev) | **no** | yes | **no** | yes | No save location on mobile, so export can't work |
| `share_plus` | share sheet only | no | share sheet only | no | Not a picker; the user has to find "Save to Files" |
| `flutter_file_dialog` 3.3.3 | yes | yes | yes | yes | Smaller community package |
| **`file_picker` 13.1.0** | **yes (SAF `ACTION_CREATE_DOCUMENT`)** | **yes (SAF)** | **yes (`UIDocumentPicker` export)** | **yes** | Verified publisher, 160/160 pub points, about 4.2M downloads in 30 days, released 15 Sep 2026; federated; Swift Package Manager on iOS |

**Choice: `file_picker` 13.1.0.** Its Android plugin manifest declares only
a `<queries>` entry for `GET_CONTENT`: no storage permission. The iOS package
supports Swift Package Manager (iOS 14+, the app targets 15). Both directions
use the system's own document UI, so the user picks the location every time.
Everything goes through the `BackupFiles` interface
(`lib/data/backup_files.dart`), and tests use an in-memory fake.

`crypto` 3.0.7 (dart.dev) provides SHA-256.

## Import validation

Validation happens before any write, in three layers:

1. **`BackupFiles.pick`:** rejects a file over **16 MiB**
   (`BackupFormat.maxBytes`) before reading it into memory. A real backup is
   tiny: an arc with every habit tracked and a reflection every night is
   about 300 KB, and the two-arc fixture is 8 KB.
2. **`BackupCodec.decode`**, in order:
   - the size, again
   - UTF-8 JSON object
   - `product == "NextRep"`
   - `formatVersion == 1`
   - checksum
   - then every field's presence and type
   - basic value rules a domain object needs: target ≥ 1, minimum within
     1..target, binary target 1, valid calendar dates, UTC timestamps,
     HH:MM times, known enum values, known achievement keys and mood keys

   **Unknown fields are rejected**, so nothing in a file is silently
   dropped. A deeply nested file is rejected cleanly.
3. **`BackupValidator.validate`**, the cross-record invariants:
   - at most one unfinished arc; unique arc ids
   - every arc is a rolling 92-day window (`end = start + 91`)
   - a completed arc has ended; a started arc didn't start after the
     export
   - habits: at least one per arc, unique id and sort order, a title like
     one the app could save (trimmed, 1–40), a target within the editing
     limits
   - every revision, progress row and habit XP entry references a habit
     of its arc
   - every date lies inside its arc and not after the export (allowing
     the exporting device's time zone; revisions may be dated one day
     later, since edits apply from the next day)
   - uniqueness: progress per habit and date, revisions per habit and
     date, modes and reflections per date, unlocks per key, XP per source
     key
   - XP source keys equal the keys the app derives
     (`habit_completed:<habit>:<date>`, `perfect_day:<date>`); a Perfect Day
     bonus has no habit
   - reflections follow the Journal's rules: trimmed, not empty, at most
     240 characters (grapheme clusters) per answer
   - an arc in setup has no history

The result is a `ValidatedBackup`. Only the validator can create one, and
`BackupStore.replaceAll` only accepts one. That makes "no mutation before
full validation" a type-level rule.

Export runs the same decode and validation on its own output before offering
the file. A backup that couldn't be restored is never saved.

Rejections map to user messages, each ending "Nothing was changed.":

- too large
- not a NextRep backup
- made by a newer version
- damaged or edited (checksum)
- contains data NextRep can't restore safely

## Restore semantics

Restore is a **full replacement**: "This backup will replace NextRep data on
this device." There is no merge.

### Confirmation

1. **Pick the file** through the system document picker. It is fully
   validated before anything is shown.
2. **Preview: Restore Backup.** It shows:
   - export date and time
   - number of arcs, and completed arcs
   - the active arc's dates, or "Arc in setup"
   - reflection count and achievement count

   No reflection text. Then: "This will replace the NextRep data currently
   stored on this device. It cannot be automatically merged with your
   current Arcs. Reminders will be off after restoring." [Cancel] [Restore]
3. **Only when the device has data: Replace current data?** "This device
   has N Arcs and M reflections. They will be permanently replaced by the
   backup. If you might need them, cancel and export a backup first."
   [Cancel] [**Replace Data**], in the destructive colour.

### Transaction and rollback

`DriftBackupStore.replaceAll` runs in **one transaction**:

1. Work out the arc id offset (below).
2. Delete every app-owned row, children first: reflections, unlocks, XP,
   day modes, progress, revisions, habits, sessions, reminder preferences.
3. Insert the backup in one batch, parents first.
4. **Verify inside the transaction:** every table's row count equals the
   backup's, at most one unfinished arc, and `PRAGMA foreign_key_check` is
   empty.
5. Commit.

Any failure in steps 1–4 (a constraint, I/O, a failed check) rolls everything
back. The data on the device stays exactly as it was.

- A test makes SQLite refuse the last insert (a temporary
  `RAISE(ABORT)` trigger on reflections) and checks that every row of every
  table is unchanged.
- A mutation check (removing the transaction) makes that test fail.

**Arc ids.** Restored arcs are shifted past every id this database has used
(`max(sqlite_sequence, max(id))`). A fresh install has used none, so it
keeps the backup's ids, and a second export is byte-identical. Over existing
data the ids are new. Anything still holding an old id then finds no arc
instead of reading or writing the restored data by mistake: a screen on its
way out, a reconcile in flight, a stale route. Order (newest = highest id)
is kept.

### Reminders after a restore

- Reminder **times** are restored. Both reminders are stored **off**, so a
  restore never starts notifications.
- Pending notifications are cancelled right after the commit.
- The app's reminder reconcile on restart finds nothing to schedule.
- The user turns reminders back on in Reminders. The restore notice says
  so: "Backup restored. Reminders are off; turn them on again in Reminders
  if you want them."

### State reconciliation

After a successful restore the app **reloads from storage, as a relaunch
would** (`AppEpoch.restart`):

- **Celebrations:** queued celebrations are dropped.
- **Boot location:** `bootLocationProvider` runs again. The arc close-out
  runs and `ArcResolution` is re-resolved; boot priority is setup → Setup,
  active → Today, completed only → latest summary, nothing → Onboarding.
  The reminder that cold-started the app only counts on the first launch.
- **Router:** while that runs nothing is routed, so the old router and
  every screen are disposed. A new router is built, keyed by the epoch.
- **Providers:** every repository provider watches the epoch. Every
  repository, service and controller that watches a service is rebuilt.
  This covers History, Journal, Achievements, Today, Journey and Insights,
  and every session-scoped provider.

The emulator showed why the last point matters. With only the remount,
Today sometimes kept its pre-restore day: the new screen re-attached to its
controller before the old one was disposed. A widget test now builds every
tab, restores, and checks Today shows the restored XP.

## Completed arc deletion

- **Domain:** `WinterArcService.deleteCompletedArc(id)` accepts only
  `WinterArcStatus.completed`. A setup or active arc is rejected with
  `arcNotDeletable`; an unknown id with `sessionNotFound`.
- **Storage:** `WinterArcRepository.deleteSession(id, expected:)` checks the
  status again inside its transaction, then deletes the session.
  - Existing `ON DELETE CASCADE` keys remove habits, modes, XP, unlocks and
    reflections; progress and revisions go via habits. `PRAGMA
    foreign_keys = ON` is set in `beforeOpen`.
  - Before committing, it verifies that none of the seven child tables has
    a row for the arc. Otherwise it rolls back.
- **Reminder preferences** belong to the app and are never touched.
- **UI:** a completed arc's summary has an overflow menu with **Delete
  Arc**. The dialog reads "Delete this Winter Arc?" with:
  - the arc's dates, total XP and Perfect Days
  - "This permanently removes its habits, progress, XP, Journey,
    achievements and reflections. This cannot be undone unless you have a
    backup."
  - [Cancel] [**Delete Arc**] in the destructive colour

  Getting there takes a menu, a dialog and a destructive button: no
  one-tap deletion.
- **Routing:** after the delete the arcs are re-resolved and the app
  navigates with `go()`, which replaces the whole stack, so no route keeps
  the deleted id:
  - while an arc runs → Arc History
  - otherwise the home: the latest remaining completed summary, or
    onboarding when none is left

  If re-reading fails after the committed delete, the app reloads from
  storage instead. Arc History and Insights re-read (`arcsChangedProvider`),
  and queued celebrations are dropped.

## Setup cancellation

- `WinterArcService.cancelSetup()` works only on the unfinished arc, and
  only while it is in setup.
  - An active arc → `sessionNotInSetup`.
  - No unfinished arc → `noSession`, which also covers "cancelling" a
    completed arc.
  - The repository re-checks the status inside its transaction.
- Habit Setup has **Cancel setup**. The dialog reads "Cancel this setup?":
  - with completed arcs: "Your previous completed Arcs will remain safe."
  - first install: "Your habit choices will be cleared. You can start
    again whenever you are ready."

  Buttons: [Keep Setup] [**Cancel Setup**].
- The setup arc and its provisional habits are deleted. Afterwards:
  - with history → the latest completed summary
  - first install → onboarding
- Cancelling an active arc is not offered.

## Insights

### Architecture

```
InsightService (domain/insights/insight_service.dart)       ← reads facts
   WinterArcRepository.listSessions()   (setup arcs skipped)
   ProgressRepository.loadArc(id)        → ArcHistory (as of today)
   ReflectionRepository.moodsFor(id)     → MoodMark {date, mood}  (no text)
        ↓
InsightRules.compute(List<InsightArc>)   (pure, insight_rules.dart)
        ↓
InsightSnapshot {overall, habits, mostConsistent, bestStreak, moods}
        ↓
insightsProvider → InsightsScreen  (widgets only display numbers)
```

- Nothing is persisted. Arcs are few, so computing on demand is cheap.
- `insightsProvider` re-reads after progress changes, reflections, a new
  arc and deleted arcs.
- Entry point: an **Insights** button on Arc History, the History tab
  while an arc runs, and `/arcs` otherwise. No fifth tab: History is where
  cross-arc questions already live.

### Scope

- Completed arcs count in full; the active arc counts up to and including
  today (`ArcHistory.elapsedDates`).
- Setup arcs and future dates are excluded.
- Today counts as an elapsed day, as on an arc's summary card, so the two
  agree.

### Overall

| Metric | Definition |
|---|---|
| Arcs | completed count; the active arc and its day number |
| Days climbed | Σ elapsed challenge days |
| Consistency | **Σ full days / Σ elapsed days**, rounded down to a whole % |
| Perfect Days | Σ normal days with every enabled habit done |
| Minimum Days completed | Σ Minimum Days with every habit at its minimum |
| Total XP | Σ ledger totals |
| Highest level | max over arcs of `LevelRules.levelFor(arc XP)` (each arc's XP is its own) |
| XP per day | total XP / days climbed |
| Reflections | reflections on elapsed days; rate = reflections / days climbed |

A full day is a Perfect Day or a completed Minimum Day. Arc percentages are
never averaged, so a tiny arc can't outweigh a 92-day one. In the tested
example, 46/92 and 4/4 give 50/96 = 52%, not 75%. With no started arc the
screen shows an empty state, and every rate is 0 rather than a division by
zero.

### Habit aggregation

- **Identity:** the stable habit id.
  - Starter habits and Reuse Last Setup keep their ids, so they are one
    habit across arcs.
  - Different ids are never merged, even with the same title.
  - A renamed habit keeps its lineage and shows its newest title. Workout
    renamed to "Strength" in Arc 1 and reused in Arc 2 is one row, titled
    Strength.
- **Applicable days:** elapsed days on which the habit was enabled (from
  its revision history). Disabled days don't lower its rate. A habit never
  enabled isn't listed.
- **Completed days:** applicable days with the habit completed. Completing
  the minimum on a Minimum Day counts.
- **Best streak:** the longest run within one arc. Arcs are separate
  climbs, so a run never carries over from one arc to the next.
- **Arcs:** the number of arcs in which it was enabled on an elapsed day.
- **Most consistent:** highest completion among habits with at least
  **7** applicable days, so 1/1 = 100% doesn't win. Ties go to more
  completed days, then the habit id.
- **Best streak highlight:** longest streak; ties go to the completion
  order above.

### Mood insights

- Counts per mood (Excellent, Good, Okay, Rough), plus reflections saved
  without a mood.
- The reflection rate.
- A timeline of the last 14 reflected days that have a mood, in date order
  across arcs.

The timeline places each dot on a row labelled with the mood; the rows are
for layout only. There is no score, no trend line, no sentiment analysis of
text and no interpretation. The footnote reads: "Moods are shown exactly as
you chose them. What you wrote is never read for insights."
`ReflectionRepository.moodsFor` selects only the date and mood columns.

### Charts

- Two small `CustomPainter`s: `RatioBar` for habit and mood bars, and
  `MoodTimeline`. No chart dependency.
- Every bar sits next to its number and label, and every row is one
  semantics node ("Water Intake: 84% done. 77 of 92 days · best streak 19 ·
  2 Arcs").
- Moods have icons and labels, so colour is never the only cue.
- The charts are static, so reduced motion has nothing to stop.
- At 2× text both screens lay out without overflow (widget test).

## Schema decision

**Schema stays v4.** Nothing new needs to be stored:

- Backups are files.
- The backup format version lives in the file.
- Insights are derived.
- Deletion and cancellation remove rows, using the existing cascades.

`drift_schemas/` v1–v4 and `schema_versions.dart` are unchanged, and the full
migration suite still passes (28/28: v1 → v2 → v3 → v4, v2 → v3 → v4,
v3 → v4, realistic fixtures).

## Tests

| Suite | Tests | Covers |
|---|---|---|
| `domain/backup_format_test` | 22 | encoding, determinism, canonical JSON, checksum = SHA-256 of the body, domain field names, rejection of product / version / checksum / malformed / oversized / two unfinished / orphans / duplicate and mismatched XP keys / targets / reflections / unknown achievements / dates, multi-unit emoji at the limit, deep nesting, no file content in failures |
| `data/backup_restore_test` | 23 | every table round-trips (completed, active, multiple arcs, habits, revisions, Minimum Days, progress, XP, achievements, reflections), reminder times restore with reminders off, empty export, boot routing after restore, inspecting never writes, failed validation changes nothing, a failed insert rolls back everything, reminders cancelled, ids never reused (stale writes rejected), re-export identical |
| `domain/arc_deletion_test` | 14 | delete completed, all seven child tables cascade, reminder preferences kept, other arcs byte-identical, fallbacks to the next latest arc and to onboarding, active and setup rejected (service and repository), cancel setup, previous arc byte-identical, first-ever cancel → onboarding, active and completed can't be cancelled |
| `domain/insight_rules_test` | 19 | setup excluded, future dates excluded, active up to today, completed in full, weighted consistency, Perfect Day and Minimum Day totals, empty history, XP and levels, disabled days, Minimum Day completion, same id across arcs, same title different ids, rename lineage, deterministic ties, best streak per arc, mood counts, rate, missing mood, chronological timeline, no text via the service |
| `features/phase5_flow_test` | 11 | export privacy dialog and save, restore preview without text, replace confirmation, reload on the restored data with reminders off, damaged file refused, restore from onboarding, Delete Arc from History and from the home summary, Cancel Setup (with and without history), Insights values and empty state, 2× text |
| `app/phase5_routes_test` | 3 | Data & Backup and Insights reachable in every state, no reminder payload reuse after a restart, `appVersion` matches pubspec |
| `integration_test/phase5_smoke_test` | 1 | real SQLite file: export (in-memory adapter), check the summary, change data, restore, all tables back, reminders off, Journal, Insights, delete Arc 1, Arc 2 intact |

Phase 1–4 tests are unchanged, apart from one fake repository that gained
`deleteSession`.

## Validation

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed .` / `flutter analyze` | clean / no issues |
| `flutter test` | **440 / 440** (Phase 4: 348) |
| `flutter test --coverage` | **93.7%** of handwritten `lib/` (excluding generated `*.g.dart` and the generated schema steps); domain 96.9%, data 96.9%, features 94.5%, shared 95.2%. `backup_files.dart` (the plugin wrapper) is covered on devices instead |
| migration tests | 28 / 28 |
| Phase 5 suites | 92 / 92 |
| integration, Android emulator (API 36) | 5 / 5 |
| integration, physical Android (CPH2707, Android 16, wireless ADB) | 5 / 5 |
| integration, iOS simulator (iPhone 17, iOS 27) | 5 / 5 |
| `flutter build apk --debug` / `--release` | built |
| `flutter build ios --simulator` | built (Swift Package Manager, `file_picker_darwin`; no CocoaPods) |
| release permission audit | below |

### Release APK permissions (`aapt2 dump permissions`)

```
uses-permission: android.permission.RECEIVE_BOOT_COMPLETED
uses-permission: android.permission.VIBRATE
uses-permission: android.permission.POST_NOTIFICATIONS
permission:      com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

| Permission | Release |
|---|---|
| `INTERNET` | **absent** |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | **absent** |
| `MANAGE_EXTERNAL_STORAGE` | **absent** |
| `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` | **absent** |

`file_picker` added no permission. Unchanged from Phase 4.

### Emulator: manual backup validation (Android 16 / API 36, release build)

| Step | Result |
|---|---|
| Fresh install → onboarding → **Restore from a backup** → system document picker (DocumentsUI, no permission prompt) → Downloads → `fixture.nextrep` | PASS |
| Preview: exported time, 2 arcs, 1 completed, active arc dates, 2 reflections, 9 achievements, no reflection text; single confirmation on an empty device | PASS |
| Restored: Today Day 1, Perfect Day, 75 XP; Journal entry; History with both arcs; Insights 93 days / 3% / 2 Perfect Days | PASS |
| Reminders after restore: times 7:30 AM / 9:15 PM kept, both switches off, 0 pending alarms (`dumpsys alarm`) | PASS |
| Export → privacy dialog → system **Save** dialog (`nextrep-backup-2026-10-04.nextrep` proposed) → "Backup saved." → file in Downloads; metadata only inspected (product, version, 2 arcs, sha256) | PASS |
| Device export's `data` section identical to the fixture it was restored from | PASS |
| Changed data (undid a habit), restored the device export: preview → **Replace current data?** ("2 Arcs and 2 reflections") → Replace Data → notice "Backup restored. Reminders are off…" | PASS |
| Today, Journey and History immediately show the restored state (75 XP, 3 of 3) | PASS after the fix (it first showed stale Today; see [State reconciliation](#state-reconciliation)) |
| Force stop and relaunch: restored state persists; in-place upgrade install keeps data | PASS |
| Altered backup (`corrupt.nextrep`) → "Can't use this file … Nothing was changed."; data unchanged | PASS |
| logcat after all of the above: no reflection text, no backup content | PASS |
| Delete Arc from a completed summary: dialog with dates, 135 XP, 1 Perfect Day → back to History, "Winter Arc deleted.", active arc intact | PASS |
| Insights scroll, charts readable with labels and numbers | PASS |

### Emulator: setup cancellation

First install → Let's Begin → **Cancel setup** → "Cancel this setup? Your
habit choices will be cleared…" → [Keep Setup] / [Cancel Setup] → back on
onboarding. PASS. (Cancelling after a completed arc is covered by widget and
domain tests.)

### Physical Android (CPH2707, Android 16 / API 36, release build)

NextRep was not installed on the phone before. Nothing else was changed:
no device settings, no other app's data. The test files pushed and
exported were removed from Downloads afterwards. The app stays installed,
with test data and both reminders off.

| Step | Result |
|---|---|
| `flutter test integration_test --no-uninstall` | 5 / 5 |
| Onboarding → Restore from a backup → system document picker → test file | PASS |
| Preview (2 arcs, 1 completed, active dates, 2 reflections, 9 achievements, no text) → Restore → Today 75 XP, 3 of 3, "Backup restored" notice | PASS |
| Reminders after restore: 07:30 / 21:15 kept, both off | PASS |
| Notification settings still work: turning the daily reminder on scheduled inexact `RTC_WAKEUP` one-shots (no exact alarm); off cancelled them all (0 pending). Notification permission was already granted on this phone, so no prompt was shown | PASS |
| Export → privacy dialog → system Save dialog in Download → "Backup saved."; data section identical to the restored file | PASS |
| Delete Arc → confirmation (135 XP, 1 Perfect Day) → History, active arc intact; Insights updated (1 day, 100%) | PASS |
| Background (Home) and resume: state intact | PASS |
| Insights scroll | works; `gfxinfo` doesn't see Flutter's surface, so no frame metrics were captured |
| Reduced motion | not toggled (a device setting); covered by Phase 3 widget tests, and the new charts are static |

### iOS

- The simulator build and all 5 integration tests pass. The Phase 5
  smoke test runs export, restore, Insights and deletion through the
  in-memory file adapter.
- The **iOS document picker** (save and open), on the simulator or an
  iPhone, was **not exercised**: no simulator UI automation is available
  here. **MANUAL REQUIRED.**
- No physical iPhone was connected.

## Limitations

- **No encryption.** A backup is protected only as well as the place the
  user keeps it. Encrypted, password-based backups need a separate,
  reviewed design.
- **No merge.** Restore replaces everything.
- **Clock-skewed data:** if the device clock was moved back past tracked
  dates, export refuses (records dated after the export), and says to fix
  the device date.
- Decoding and validation run on the UI isolate. That's instant for real
  backups (KBs), but a file near the 16 MiB cap would make the app stutter
  briefly while it's checked.
- A restore keeps its own write queue. Other services' reconciles aren't
  paused, but restored arcs never reuse an id, so a late write for an old
  arc finds nothing.
- Insights count today as an elapsed day (like the summary), so an
  unfinished today lowers today's rate until it's done.
- No undo for deleting an arc, except restoring a backup.

## Phase 6 handoff

1. **Seasonal Winter Arc preset (Oct 1 → Dec 31):** needs a product design
   first: late joining, pre-season scheduling, day numbering and how it
   sits next to the rolling arc. Deliberately not started.
2. **Physical-device follow-ups:** iOS document picker and notification
   delivery on an iPhone; TalkBack pass on a phone.
3. **Optional encrypted backup:** a passphrase-derived key (Argon2id or
   scrypt) + AES-GCM, as format 2. Needs a review and a recovery story.
4. **Custom habits during setup**, and a time-based "Sleep Before Target"
   habit type: both need history semantics designed first.
5. **Journey polish:** restrained parallax and per-chapter scenery,
   respecting reduced motion.
6. Moving backup decoding to a background isolate if large backups ever
   become realistic.
