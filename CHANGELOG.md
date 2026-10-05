# Changelog

NextRep's release history, by development phase. Each phase was reviewed and
merged as one pull request. No version has been published to a store yet.
The first public version number will be chosen at release (see
[docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)).

Data compatibility is listed per phase: the on-device database schema
version and the backup file `formatVersion`. Every schema upgrade is a
tested migration from every earlier version.

## Unreleased: Phase 7, release readiness and premium UX

Schema **v5** (unchanged) · backup format **2** (unchanged, still reads 1)

### Added
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

### Changed
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

## Phase 6: Seasonal Winter Arc and habit evolution (#6)

Schema **v5** · backup format **2** (reads 1)

- Arc kinds: the Rolling 92-Day Arc and the Seasonal Winter Arc
  (1 October – 31 December), with September setup and late joining. Days
  before joining are neutral everywhere.
- Habit Setup v2: a template catalogue, custom habits, and edit and remove
  in setup, up to 12 habits.
- Clock-time habits ("before a time") and Sleep Before Target.
- Backup format 2; format-1 backups still restore.

## Phase 5: data safety, backup and cross-Arc insights (#5)

Schema **v4** · backup format **1**

- Export and restore of a versioned, checksummed backup file through the
  system document UI. Validated before anything changes, and restored in
  one transaction that rolls back on failure.
- Delete a completed arc; cancel a setup.
- Insights across arcs: consistency, Perfect and Minimum Days, XP, per-habit
  completion and moods.

## Phase 4: retention, Arc history and local reflections (#4)

Schema **v4**

- Start a new arc from the last summary (reuse the setup or start fresh).
- Arc History, and read-only past summaries, Journeys and Journals.
- The Journal: a nightly 20-second reflection.
- Optional local reminders, off by default.
- 15 achievements.

## Phase 3: Winter Arc visual experience and achievements (#3)

Schema **v3**

- The Winter scene, the Today hero and the Journey mountain path in six
  chapters.
- 10 achievements with celebrations. Goal edits apply from the next day.
- The arc closes after Day 92 and opens its summary. GitHub Actions CI.

## Phase 2: habit loop depth and Journey foundation (#2)

Schema **v2**

- Streaks, Perfect Days and their bonus, levels.
- Minimum Day, habit editing, the Today / Journey shell, Journey v1.

## Phase 1: foundation and Day 1 (#1)

Schema **v1**

- The Winter Arc theme, onboarding, habit setup and Today.
- Binary, count and duration habits, the idempotent XP ledger, and local
  SQLite storage that survives restarts.
