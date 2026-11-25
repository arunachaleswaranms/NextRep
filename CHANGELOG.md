# Changelog

## 1.3.0 — release candidate (not yet published)

Installs over 1.2.0 and keeps your data: the database moves from schema v6
to v7 on first launch, only adding to it. Release notes:
[docs/releases/v1.3.0.md](docs/releases/v1.3.0.md). Built in Phases 12E1
(#24), 12B (#25), 12C (#26), 12D (#27), 12E2 (#28), 12F (#29) and 12G
(#30), integration-qualified in Phase 12H (#31,
[docs/PHASE_12H.md](docs/PHASE_12H.md)) and release-qualified in Phase 12I
([docs/PHASE_12I.md](docs/PHASE_12I.md)). Version `1.3.0+4`.

Schema **v7** · backup format **4** (reads 1, 2, 3 and 4)

### Added

- **Weekly Arc Review**: open "Week N review" from the Journey to see a
  week of your Arc (Days 1–7, 8–14, … and an 8-day summit week): habit
  completion, consistency, XP, Perfect Days and Minimum Days for the days
  that are over, today's progress kept apart until it ends, the habit that
  carried the week and one that could use attention, and a short,
  supportive summary. Works for the current Arc and for finished Arcs in
  Arc History. Read-only: viewing a review never changes XP, progress or
  achievements, and nothing is stored or sent.
- **Arc Consistency Calendar**: a Path | Calendar switch on the Journey
  shows the same 92 days as 13 Arc-week blocks (Week 13 holds 8 days),
  each day with its number and the Journey's shape, fill and icon:
  Perfect, Minimum complete, partial, no progress, today, upcoming, before
  you joined and not reached. Each week's heading shows its dates and how
  many finished days were full, and opens that week's review. Pauses show
  as a row between days; days before a late Seasonal join stay neutral.
  Works for the current Arc and for finished Arcs. Read-only: nothing is
  stored, awarded or sent, and the view isn't remembered.
- **Habit order in setup:** put an Arc's habits in your order before it
  starts: drag a card by its handle (or touch and hold it), use Move up /
  Move down in its menu, or the screen reader's Move up / Move down
  actions. The order is saved at once and is the order of Today, the
  Journey and the Weekly Review once the Arc starts. A running Arc's order
  stays fixed.
- **Save for Later and the saved-setup hub:** your setup is saved as you
  edit it; "Save for Later" confirms it and opens the hub, which is also
  where NextRep opens while a setup exists (after a restart or a restore).
  From it: Start Challenge, Review Setup, Continue Editing, Reminders,
  Data & Backup, Focus Guard (Android), Arc History and About.
- **Review Setup and Confirm & Start:** review the Arc's habits, goals,
  Minimum Day goals, the habits that are off and your reminders, then
  confirm on a separate screen that shows Day 1 and Day 92 (or the season
  day you join on). A Rolling Arc's Day 1 is the day you confirm.
- **Pause and Resume (Rolling Arcs):** "Pause Arc" (Today ⋮ or Habits)
  pauses an active Rolling Arc from tomorrow; today still counts. Until
  midnight a banner offers Cancel pause. Paused days are never missed
  days: nothing can be logged, reminders stop, and Focus Guard keeps its
  own schedule. "Resume Arc" makes today the next challenge day and moves
  the last day later by the paused days. Summary and Arc History show the
  days paused. Never offered for a Seasonal Arc or on Day 92, and refused
  while the phone's date is earlier than the Arc's history.
- **Restart with this setup:** from the Habits screen or the paused
  Today, start a new Rolling 92-Day Arc on Day 1 today with the same
  habits, goals (including a change waiting for tomorrow), on/off states
  and order. Type RESTART to confirm. The current Arc is kept in Arc
  History as "Ended early · Day N of 92": its progress, XP, achievements,
  reflections and goal history stay exactly as they were, it is never
  called completed and never earns the Summit. The new Arc starts at 0 XP
  with its own streaks and achievements. A pause that was scheduled or in
  effect ends with the old Arc. For a Seasonal Arc the entry reads "Start
  a Rolling Arc with this setup"; the season's dates never move. Refused,
  with nothing changed, while the phone's date is earlier than the Arc's
  history.
- **Delete an old Arc (optional, typed DELETE):** after a restart you can
  choose "Delete my old Arc…", which opens a separate screen once the new
  Arc has started. It lists exactly what will be lost (challenge days,
  XP, achievements, reflections, including zeros) and offers a backup
  first; nothing is deleted unless DELETE is typed. Leaving the screen, or
  the app closing, keeps the old Arc. The same screen now deletes any
  finished Arc from its summary.
- **Completion sounds:** a short, original sound when a saved habit
  action completes a habit (a binary habit marked done, a count or
  duration reaching its target, a bedtime logged at or before its goal),
  and a longer Perfect Day sound instead of it for the completion that
  makes today perfect. Nothing plays for steps below a target, undo,
  Minimum Day, level-ups, achievements, opening the app, midnight or a
  restore. At most one sound every half second and one per habit every 3
  seconds; extra ones are dropped, never queued. Sounds follow the
  phone's sound settings: silent on silent, vibrate and Do Not Disturb,
  and music keeps playing. Three sets (Ice Crystal, the default; Summit
  Spark; Warm Ember), bundled in the app and generated for NextRep from
  source in `tool/sounds/`. Haptics are unchanged.
- **Sound & Feedback** settings: completion sounds on or off (on by
  default) and the set, each with a Play preview. Reachable from Today
  (beside Reminders), the saved-setup hub, Arc History and About, in
  every state. App-level: kept across restarts and Restart; a format-4
  backup restores it, an older backup keeps this device's setting.

### Changed

- **Today's header:** when "WINTER ARC" and its buttons don't fit on one
  line (narrow phones, larger text), the buttons move to a row beneath it
  instead of squeezing the title.

- **Deleting a completed Arc** now uses the typed-DELETE screen instead of
  a confirmation dialog (owner decision O11), the same as an Arc ended
  early.
- **Journey wording (Gate C):** a past day with no progress reads
  "No progress" instead of "Missed" in the Journey, the Calendar, the
  Legend, the Weekly Review's day strip, day details and screen-reader
  announcements. Wording only: nothing is re-scored and no data changes.
- The Journey Legend includes "Not reached" for an Arc ended early.
- **Starting an Arc** takes Review & Start → Continue to Start → Confirm &
  Start Challenge (or Confirm & Join Season); Habit Setup no longer starts
  an Arc with one tap. Starting never uses a date the screen didn't show.
- **Easier-to-read primary buttons:** filled buttons (Let's Begin, Start
  Challenge, Confirm, Share, …) now use dark text on the blue, about
  6.9:1 contrast instead of 2.61:1. Sizes, actions and the unavailable
  look are unchanged.
- **Database schema v7** (additive, one atomic step): freeze intervals
  (`arc_freezes`), the closing date of an Arc ended early
  (`winter_arc_sessions.closed_on`) and sound settings
  (`feedback_preferences`). Every existing row is kept unchanged.
- **Backup format 4**: also holds paused and ended Arcs and the sound
  settings. Formats 1, 2 and 3 still restore, with no pause and the
  device's own sound setting. NextRep 1.2.0 and earlier refuse a format-4
  file without changing anything.
- Focus Guard's background check reads schema v7.
- Internal: challenge days are mapped to dates through one freeze-aware
  mapping; an `ended` Arc is never treated as completed (no Summit).

### Fixed (Phase 12H)

- **Restart on the day you resume:** "Restart with this setup" on the
  day a paused Arc was resumed, before anything was logged that day, said
  "Couldn't restart. Nothing was changed." It now restarts; the old Arc
  ends on that day (the same as restarting the next morning) and keeps
  its pause in Arc History.
- **Readable destructive buttons:** the red "Cancel Setup" and "Replace
  Data" buttons now use dark text (about 6.7:1 contrast instead of 2.7:1),
  like "Delete Arc".

### Privacy / compatibility

- No new Android permission (the same seven as 1.2.0), dependency or
  network request; the manual update check is still the only request, and
  only when tapped. Completion sounds are bundled; only the on/off choice
  and set are stored. No analytics, account, backend or cloud sync.
- Same application id (`com.nextrep.nextrep`) and signing certificate as
  1.0.0, 1.1.0 and 1.2.0, so it updates in place.
- Backups from 1.0.0, 1.1.0 and 1.2.0 (formats 1, 2 and 3) restore into
  1.3.0. A 1.3.0 backup (format 4) can't be restored into 1.2.0 or
  earlier, which refuse it unchanged.

## 1.2.0 — 2026

Published on 18 October 2026 as the
[v1.2.0 GitHub Release](https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0)
(tag `v1.2.0` on `8ab0c43`; APK SHA-256
`e384762832a8c3fa697e84fc4951c9adfd48fa65c7bce52e66723b4883bde3e2`).

Installs over 1.1.0 and keeps your data. Release notes:
[docs/releases/v1.2.0.md](docs/releases/v1.2.0.md). Built in Phases 11A
(#15), 11B (#16), 11C (#17) and 11D (#18), integration-qualified in Phase
11E (#19) and release-qualified in Phase 11F
([docs/PHASE_11F.md](docs/PHASE_11F.md)).

Schema **v6** · backup format **3** (reads 1, 2 and 3)

### Added

- **Hydration Coach**, off by default: up to 3, 4 or 5 nudges a day
  (Gentle, Balanced, Supportive) within active hours you choose, paced
  against the Arc's built-in Water habit, only when you're behind. Local
  notifications; a tap opens Today.
- **Focus Guard** (Android), off by default: chosen launcher apps share one
  daily budget (default 60 minutes); Today shows the time used, and a
  background check sends at most one reminder per day when the budget is
  reached. Needs Android's Usage Access. Never blocks apps; no XP, streak
  or achievement effect; no usage history is stored.
- **About NextRep**: the installed version and build, privacy, the official
  source and licenses. On Android, a manual **Check for updates** that asks
  GitHub for the latest published release only when tapped, and opens its
  page in the browser. It never downloads or installs anything.

### Changed

- The database moves from schema v5 to **v6** on first launch, keeping all
  existing data; Hydration Coach and Focus Guard start off, and existing
  reminders are unchanged.
- Backups are written as **format 3** (Hydration Coach settings, Focus
  Guard apps and budget). Formats 1 and 2 still restore. A restore turns
  every reminder, Hydration Coach and Focus Guard off.
- At large text, Focus Guard's budget shows under its title instead of
  squeezing it (Phase 11E).

### Privacy / compatibility

- New Android permissions: `INTERNET` (the manual update check only),
  `PACKAGE_USAGE_STATS` (Focus Guard's Usage Access, granted by the user in
  system settings) and `WAKE_LOCK` (WorkManager). Still no analytics,
  account, backend or cloud sync; nothing goes online by itself.
- Same application id (`com.nextrep.nextrep`) and signing certificate as
  1.0.0 and 1.1.0, so it updates in place.
- 1.0.0 and 1.1.0 backups restore into 1.2.0. A 1.2.0 backup (format 3)
  can't be restored into 1.1.0 or earlier, which refuse it unchanged.

## 1.1.0 — 2026

Installs over 1.0.0 and keeps your data. Release notes:
[docs/releases/v1.1.0.md](docs/releases/v1.1.0.md). Built in Phases 10A
(#11), 10B (#12) and 10C (#13), and qualified in Phase 10D
([docs/PHASE_10D.md](docs/PHASE_10D.md)).

Schema **v5** · backup format **2** (reads 1 and 2)

### Added

- **Share cards**: Today's Progress, My Arc and an unlocked achievement,
  each a 1080 × 1350 PNG made on the device and handed to the system share
  sheet when you tap Share. Today's Progress can hide habit names, XP &
  level and the streak. No account, no social graph, no automatic posting.
  Cards carry subtle NextRep branding only: no repository link in the image
  or in the share caption.
- **Six optional habit templates** for Arc setup: Hair Care, Skin Care, Eat
  Fruit, Nuts / Seeds, Stretch / Mobility and Reading. They aren't added to
  an Arc that is already running.
- **17 new achievements** (32 in all) in six categories: Progress,
  Consistency, Resilience, Habit Mastery, Reflection and Journey. Longer
  streaks and Perfect Day counts, Minimum Day resilience, reflection and
  journey milestones, and activity milestones for No Junk Food, Workout,
  Water, Learning and Sleep Before. Achievements still give 0 XP.
- Existing history is **backfilled** against the new achievements on first
  launch, dated when it earned them. The current Arc's new unlocks are
  celebrated together once; completed Arcs are filled in silently.

### Changed

- **Minimum Day can be undone the same day**: Undo on the snackbar, or
  "Return to full targets" on the banner. Progress is kept, and completion
  and XP are worked out again. Past days never change.
- Achievements unlocked today follow today's history, so undoing a habit or
  a Minimum Day can take back today's unlock. Earlier unlocks never change.
- **Sleep Before Target** reads as "Last night's bedtime", counted for
  today. Custom clock-time habits keep neutral wording.
- The Achievements screen is grouped by category.
- Motion: the Minimum Day target change eases instead of snapping, and the
  share preview reveals once. Reduced motion turns both off.

### Privacy / compatibility

- Still local-first: no account, server, analytics, ads or cloud sync. The
  Android release still has no `INTERNET` permission, and sharing needs no
  storage, media, photo or contacts permission.
- [PRIVACY.md](PRIVACY.md) now covers share cards: nothing is sent
  automatically, and a card leaves the app only when you share it.
- Same application id (`com.nextrep.nextrep`) and signing certificate as
  1.0.0, so it updates in place. No data migration.
- 1.0.0 backups restore into 1.1.0. A 1.1.0 backup that holds one of the
  new achievements can't be restored into 1.0.0.

## 1.0.0 — 2026

First public release, distributed as a signed Android APK on GitHub
Releases. Release notes: [docs/releases/v1.0.0.md](docs/releases/v1.0.0.md).

Schema **v5** · backup format **2** (reads 1 and 2)

NextRep's Winter Arc is a private, local-first 92-day habit challenge:

- Rolling 92-Day and Seasonal Winter Arcs (1 October – 31 December, with
  late joining).
- Template and custom habits, including clock-time habits and Sleep Before
  Target.
- Streaks, XP, levels, Perfect Days and Minimum Day.
- The Journey mountain path, 15 achievements, the nightly Journal, Arc
  History and cross-arc Insights.
- Optional local reminders, and backup and restore to a `.nextrep` file.
- No account, server, analytics or cloud sync. The Android release has no
  Internet permission.

## Development history

The entries below record each development phase before 1.0.0. Each phase
was reviewed and merged as one pull request. None of them was published as
a release.

Data compatibility is listed per phase: the on-device database schema
version and the backup file `formatVersion`. Every schema upgrade is a
tested migration from every earlier version.

### Phase 9: GitHub release and self-distribution

Schema **v5** (unchanged) · backup format **2** (unchanged, still reads 1)

- Version 1.0.0 (1). The Android application id stays `com.nextrep.nextrep`.
- A permanent Android release signing key, and a release script that
  builds, verifies and stages the signed APK with its checksum.
- Release APKs are byte-reproducible: AGP's Play-only dependency block is
  left out.
- MIT license. README install, update and build-from-source guides, a
  direct-distribution guide and the v1.0.0 release notes.
- Google Play and App Store publication is no longer planned.

### Phase 8.5: physical Android qualification (#9)

Schema **v5** (unchanged) · backup format **2** (unchanged, still reads 1)

#### Fixed
- Screen readers hear "not logged" once, not twice, on a bedtime habit
  that has no time yet.

#### Added
- Release qualification on a physical Android phone (OnePlus CPH2707,
  Android 16): an in-place install, real reminders including after a
  reboot, document-picker backups, 2× text, reduced motion and profile
  frame timings. The human TalkBack pass is still open. See
  `docs/PHASE_8_5_PHYSICAL_ANDROID.md`.

### Phase 8: store launch and physical qualification (#8)

Schema **v5** (unchanged) · backup format **2** (unchanged, still reads 1)

#### Fixed
- At large text, the level and XP next to the XP pill (Today, Journey)
  wrap instead of being cut to "Le…".
- Screen readers hear "1 reflection", "1 Perfect Day" and "N of 15
  achievements" on Arc History cards, and no doubled period on the Arc
  choice cards.

#### Added
- A dev-only generator for a synthetic screenshot backup
  (`tool/screenshots/`). It isn't part of the app.
- Release qualification of the release build on the emulator: an upgrade
  from schema v4 and v5 data, notifications, document-picker backups, 2×
  text and "Remove animations". See `docs/PHASE_8.md`.

### Phase 7: release readiness and premium UX (#7)

Schema **v5** (unchanged) · backup format **2** (unchanged, still reads 1)

#### Added
- NextRep branding: an app icon generated from one vector geometry
  (adaptive and themed Android icons, every iOS size, store icons), a night
  launch screen with no white flash, and the "NextRep" display name.
- The app moves to the new day at local midnight while it stays open, and
  an arc that ends at midnight opens its summary straight away.
- Calm failure states: "Go home" for an arc that is no longer on the
  device, a page for unknown links, a release-mode error panel, labelled
  loading and intentional empty states.
- Release documents: privacy, store readiness and metadata, the release
  checklist, Android signing.
- CI: release qualification tests, a release APK compile and a release
  permission audit.

#### Changed
- Onboarding explains the climb, custom habits, Rolling vs Seasonal and
  on-device privacy, and keeps "Let's Begin" on screen at any text size.
- The Arc choice says that days before a late join don't count, and shows
  the closed season as a calm "not yet".
- Screen-reader controls now carry their tap action. Journey days say
  their state in words ("Day 15. Today. 60 percent complete.") and have a
  56 dp touch target. Binary habits expose a checked state. Celebrations
  wait for dismissal when a screen reader is on.
- Large text: the Summary heading, Journey header, progress ring, day
  detail and mood rows scale or scroll instead of clipping.
- Backup copy: the checksum detects accidental corruption, nothing more.
- Reminders: a failing permission check no longer blocks the settings
  screen; a scheduling failure after saving says the setting was saved.
- Release builds no longer print framework errors to the system log.

### Phase 6: Seasonal Winter Arc and habit evolution (#6)

Schema **v5** · backup format **2** (reads 1)

- Arc kinds: the Rolling 92-Day Arc and the Seasonal Winter Arc
  (1 October – 31 December), with September setup and late joining. Days
  before joining are neutral everywhere.
- Habit Setup v2: a template catalogue, custom habits, and edit and remove
  in setup, up to 12 habits.
- Clock-time habits ("before a time") and Sleep Before Target.
- Backup format 2; format-1 backups still restore.

### Phase 5: data safety, backup and cross-Arc insights (#5)

Schema **v4** · backup format **1**

- Export and restore of a versioned, checksummed backup file through the
  system document UI. Validated before anything changes, and restored in
  one transaction that rolls back on failure.
- Delete a completed arc; cancel a setup.
- Insights across arcs: consistency, Perfect and Minimum Days, XP, per-habit
  completion and moods.

### Phase 4: retention, Arc history and local reflections (#4)

Schema **v4**

- Start a new arc from the last summary (reuse the setup or start fresh).
- Arc History, and read-only past summaries, Journeys and Journals.
- The Journal: a nightly 20-second reflection.
- Optional local reminders, off by default.
- 15 achievements.

### Phase 3: Winter Arc visual experience and achievements (#3)

Schema **v3**

- The Winter scene, the Today hero and the Journey mountain path in six
  chapters.
- 10 achievements with celebrations. Goal edits apply from the next day.
- The arc closes after Day 92 and opens its summary. GitHub Actions CI.

### Phase 2: habit loop depth and Journey foundation (#2)

Schema **v2**

- Streaks, Perfect Days and their bonus, levels.
- Minimum Day, habit editing, the Today / Journey shell, Journey v1.

### Phase 1: foundation and Day 1 (#1)

Schema **v1**

- The Winter Arc theme, onboarding, habit setup and Today.
- Binary, count and duration habits, the idempotent XP ledger, and local
  SQLite storage that survives restarts.
