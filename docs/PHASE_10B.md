# Phase 10B: Shareable Cards & Meaningful Motion

## Objective

The second of the v1.1 phases. Two related changes:

1. **Share cards.** Three privacy-conscious image cards the user can share
   through the operating system's share sheet: Today's Progress, My Arc and
   Achievement.
2. **Meaningful motion.** Two small transitions that explain a state change,
   and nothing that only decorates.

NextRep stays local-first: no account, backend, network, analytics, social
graph or automatic posting. A card leaves the app only when the user taps
Share, and only through the system share sheet. The version stays
**1.0.0+1**. No tag, no GitHub Release, no APK.

## Baseline

| | |
|---|---|
| `main` | `ba72cf04f1761471f5f8b5e8d5ecb2da8c911d94` (PR #11, Phase 10A, merged 2026-10-11), clean tree, matches the expected baseline |
| `v1.0.0` tag | present, on `b3f9c5c`; GitHub Release "NextRep v1.0.0" is Latest |
| `v1.1.0` | no tag, no release |
| Branch | `phase/10b-sharing-motion`, from `ba72cf0` |

## Share architecture

```
DaySummary / AchievementBoard (persisted read models)
        │  pure, immutable snapshots; privacy applied here
        ▼
TodayShareCardData · ArcShareCardData · AchievementShareCardData
        │
        ▼
TodayShareCard · ArcShareCard · AchievementShareCard   (fixed 360×450 canvas)
        │  RepaintBoundary.toImage(pixelRatio: 3)
        ▼
ShareCardCapture → 1080×1350 PNG bytes (memory only)
        │
        ▼
ShareGateway (shareGatewayProvider) ── SystemShareGateway → share_plus
                                    └─ FakeShareGateway in tests
```

| Piece | File | Role |
|---|---|---|
| Snapshots | `lib/features/share/share_card_data.dart` | `TodayShareCardData`, `ArcShareCardData`, `AchievementShareCardData`, `SharePrivacyOptions`. Built from `DaySummary` / `AchievementStatus` only. A hidden value is null in the snapshot, so it can't reach the card, its semantics, the file name or the share text |
| Cards | `lib/features/share/widgets/share_cards.dart`, `share_card_frame.dart` | One visual family; render a snapshot and decide nothing |
| Capture | `lib/features/share/share_card_capture.dart` | The card's own `RepaintBoundary` → PNG at pixel ratio 3 |
| Preview | `lib/features/share/share_preview_screen.dart` | Shows the exact card, privacy switches (Today only), Share / Cancel, tap guard, error message |
| Choice | `lib/features/share/share_choice_sheet.dart` | "Share your Arc": Today's Progress or My Arc |
| Achievement details | `lib/features/achievements/widgets/achievement_detail_sheet.dart` | Badge, criterion, unlock day, "Share <title>" |
| Gateway | `lib/data/share_gateway.dart` | `ShareGateway` interface, `ShareFile.png`, `SystemShareGateway`; provider in `lib/app/dependencies.dart` |

The domain layer is untouched: no platform or sharing code is in it.
Sharing performs **no database writes** (asserted in the tests).

## Dependency

| Package | Version | Kind | Why |
|---|---|---|---|
| `share_plus` | **13.3.1** (`^13.3.1`) | new direct | The system share sheet. Flutter Favorite, Flutter Community publisher, current stable. Uses the instance API `SharePlus.instance.share(ShareParams(...))`; the deprecated static `Share.share*` APIs are not used |
| `path_provider` | 2.1.6 (`^2.1.5`) | transitive → direct | The app's private cache directory for the staged PNG. Already shipped in v1.0.0 (through `drift_flutter`) at the same locked version, so nothing new is built |

New lock entries: `share_plus`, `share_plus_platform_interface` 7.2.0, and
`url_launcher_linux` / `_web` / `_windows` / `_platform_interface` (used by
`share_plus` on desktop and web only; there is no `url_launcher_android` or
`_ios`). No existing locked version changed.

Compatibility checked before adding it:

| Requirement of `share_plus` 13.3.1 | NextRep |
|---|---|
| Flutter ≥ 3.38.1, Dart ≥ 3.10 | Flutter 3.47.5, Dart 3.13.4 |
| Android minSdk 21, Java / JVM 17, Kotlin plugin 2.2 | minSdk 24 (Flutter default), Java 17, Kotlin 2.4.0, AGP 9.1.0, Gradle 9.3.1: builds |
| iOS 13 (Swift Package Manager) | iOS 15 deployment target, SPM: builds |
| Android manifest | a `FileProvider` (`exported="false"`, `cache/share_plus/` only) and a receiver for the chosen target (`exported="false"`). **No permissions, no `<queries>`** |

It adds no networking. Its Android code only builds a chooser intent with a
content URI; its iOS code presents `UIActivityViewController`. The share
text is plain text with no link; `ShareParams.uri` (which makes iOS fetch a
page preview) is not used.

## Native share behavior

- PNG is the primary artifact (`image/png`). The short accompanying text
  names the arc and day or the achievement, then "— NextRep" (for example
  `My Winter Arc · Day 24/92 — NextRep`). No link, no habit data, no
  tracking or referral parameters, no ids. The image stands alone if a
  receiving app drops the text.
- File names: `nextrep-day-<n>.png` (`nextrep-today.png` outside the arc's
  window), `nextrep-my-arc.png`, `nextrep-achievement-<slug>.png`. The slug
  keeps only `a–z`, `0–9` and single hyphens (≤ 40 characters).
- Closing the sheet without sharing (`dismissed`) or a platform that can't
  report (`unavailable`) is normal: no message, no XP, no achievement, no
  database change.
- A failure to open the sheet shows "Couldn't open the share sheet." once,
  never retries, and Share works again.
- Repeated taps: while a share is being prepared or the sheet is open, Share
  is disabled and further taps do nothing, so only one sheet opens.
- iPad: the popover is anchored to the Share button
  (`sharePositionOrigin`).
- iOS: **Save Image** and **Assign to Contact** are excluded from the sheet,
  so sharing never needs photo-library or contacts access (Save Image
  without a usage string would also crash).

### Temporary files

- The PNG is rendered in memory.
- `SystemShareGateway` writes it to `<app cache>/nextrep_share/<file name>`
  (app-private, no permission), shares it, and deletes the folder when the
  sheet closes. A folder left by an interrupted share is removed before the
  next one.
- On Android `share_plus` copies the file into `<app cache>/share_plus/` and
  grants the chosen app read access through its non-exported
  `FileProvider`. That copy stays until the next share (the plugin clears
  the folder) or until the OS reclaims cache.
- Nothing is written to Downloads, Pictures or the gallery. There is no
  share history.

## The three cards

All cards are **1080 × 1350 PNG** (4:5): a fixed 360 × 450 logical canvas at
pixel ratio 3, independent of screen width, pixel density, system text scale
and app chrome. A test renders the same card on a 1080×2400 @3× phone and a
1600×2560 @2× screen at 2× text, with and without the debug banner: the
PNGs are **byte-identical**.

Every card: a still night sky with aurora and mountains (the app's own
`SkyPainter`, `AuroraPainter`, `MountainPainter`, no ambient motion), the
NextRep mark, a tagline, and at the bottom "Made with NextRep" in small
secondary type. No link is printed on a card.

### 1. Today's Progress

Entry: a **Share progress** button in Today's header → "Share your Arc"
sheet → **Today's Progress** → preview.

Shows: `WINTER ARC · DAY 24 OF 92` (or `SEASONAL WINTER ARC · …`; day
numbers count from Day 1 as everywhere in the app), `6 / 7 COMPLETE`, a
`MINIMUM DAY` or `PERFECT DAY` pill when it applies (a Minimum Day is never
shown as a Perfect Day), every enabled habit with done / not done, and
optionally level, total XP and a streak.

- Up to the maximum 12 habits: one column up to six, two above; row height
  comes from the space left, titles are single-line with ellipsis on the
  image (the app keeps full names).
- Sleep Before Target is done / not done like any habit. **No time is ever
  shown** (not the logged bedtime, not the target).
- Streak: the current **Perfect Day streak** if there is one, otherwise the
  **best active habit streak**, labelled exactly so. No "overall" streak is
  invented.

Privacy switches in the preview, all on by default, for this preview only
(not saved, no schema change):

| Switch | When off |
|---|---|
| Show habit names | Rows become anonymous dots (no names, no icons) with "N of M habits complete"; the count stays |
| Show XP & level | Neither appears on the image or in the card's semantics |
| Show streak | No streak on the image or in its semantics |

### 2. My Arc

Entry: Today's Share progress → **My Arc** → preview.

Shows: `MY 92-DAY WINTER ARC` + "Rolling 92-day Arc", or `MY SEASONAL WINTER
ARC` + "Winter season 2026 · 92 days"; each habit with its full goal ("30
min", "8 glasses", "Before 23:30", "Daily goal"); `DAY 1 → DAY 92`, or
`JOINED DAY 15 → DAY 92` for a seasonal arc joined late (it never claims Day
1); "I'm committing to showing up."

- Source: today's `DaySummary`. The habits **enabled today** with their
  **normal targets in effect today** (`HabitDayEntry.config.target`), never
  Minimum Day targets, also on a Minimum Day. An edit saved for tomorrow
  appears from tomorrow, consistent with the rest of the app. No new
  abstraction or schema was needed.
- No calendar dates. The season year is the challenge's name, not a
  personal date.
- Up to 12 habits in a two-column grid, single-line titles with ellipsis.

### 3. Achievement

Entry: tap an **unlocked** achievement in the collection → detail sheet
(badge, title, criterion, "Unlocked on Day 12") → **Share <title>** →
preview. Works for the current arc and for past arcs' boards.

Locked achievements are not buttons: no tap action, no sheet, no share.

Shows: the badge, the title, its criterion, `UNLOCKED · DAY 12` (challenge
day, no calendar date), "Consistency beats intensity."

## Never shared

A card, its file name and its text never contain:

- Journal wins, improvements or any reflection text; moods
- backup contents or backup file names
- reminder settings
- logged clock times, including last night's bedtime
- system paths, device identifiers, account data, debug or signing data
- calendar dates (only challenge days)

None of these is read by the share code: the snapshots are built from
`DaySummary` and `AchievementStatus`, which carry none of them. NextRep
doesn't inspect contacts, apps or social networks and doesn't know where a
card goes.

Logging: the share code reports only a failure (to the local
`dart:developer` log, a no-op in release builds). It never logs habit
titles, times, image bytes or reflection data.

## Preview UX and accessibility

- `Share Today's Progress` / `Share My Arc` / `Share Achievement` app bar
  with Close; the card scaled to fit (at most 55% of the screen height);
  "This is the image that will be shared"; the switches (Today only);
  **Share**; **Cancel**. Everything scrolls.
- The preview card is one image node whose label is built from the same
  privacy-filtered snapshot ("Today's Progress card. Winter Arc, Day 24 of
  92. 6 of 7 habits complete. …"). A hidden value is not in it.
- At 2× text the preview, switches, Share and Cancel stay reachable (tests),
  and nothing overflows. Interactive text is never clamped.
- The **exported image** uses its own fixed type scale (no text scaling
  inside the card): it is a designed bitmap, not an interactive surface.
- Share progress has a tooltip and a 48 dp target; the achievement card
  exposes a tap action with the hint "show details and share" only when
  unlocked; the detail button reads "Share <title>".

## Motion audit

Existing motion (all through `context.motion`, all collapsing under reduced
motion): animated progress bars and level bar, check-icon scale/fade, hero
warmth and Minimum Day chip, achievement reveal and collection bar, Journey
marker state / glow / milestone, celebration overlay, ambient winter scene
(the only loop).

### Added

1. **Minimum Day target transition** (`HabitProgressTile`). Switching
   Normal ⇄ Minimum changes the effective target (8 glasses → 3). The
   progress label and the `MINIMUM` chip now switch with a short fade and a
   slight rise (`AnimatedSwitcher`, `context.motion.standard` = 300 ms),
   keyed to `(effective target, mode)`. An ordinary + / − keeps the key, so
   the label updates in place without a transition. The card doesn't
   bounce; the progress bar keeps animating its ratio as before. Binary
   habits get the same treatment for the chip. Clock-time habits keep their
   target on Minimum Days, so nothing changes for them.
2. **Share preview reveal.** The preview card fades in from 0 and scales
   0.98 → 1.0 once (`context.motion.standard`). Toggling a switch doesn't
   replay it. The reveal wraps the card's `RepaintBoundary`, so the export
   is always the still card at full size.

### Deliberately not added

- **Journey:** existing Journey motion already communicates persisted
  state; no redundant Phase 10B animation added. A "today node completes"
  animation would replay on every visit and imply an event that didn't just
  happen.
- **Celebrations:** unchanged in length and intensity. The achievement
  share preview uses the same one-time preview reveal, not the celebration
  system.
- No animation inside a share card, no new loop, no confetti or particle
  package, no new dependency for motion.

### Reduced motion

Both transitions read `context.motion`, so with the platform's
remove-animations setting the new target and chip appear on the first
frame, the preview is fully visible on its first frame, and no transient
callbacks remain (tests). Content and actions are the same either way.

## Compatibility locks

| | Result |
|---|---|
| Database schema | **v5**, no migration; `lib/core/database/` and `drift_schemas/` unchanged |
| Backup | export **2**; import **1 and 2**; unchanged |
| `applicationId` / iOS bundle id | `com.nextrep.nextrep` / unchanged |
| `pubspec.yaml` version | `1.0.0+1` |
| `AchievementKey` ids, habit ids, XP rules | unchanged |
| Persisted settings | none added (privacy switches live in the preview only) |
| `android/`, `ios/` | unchanged (`git diff main -- android ios` is empty) |
| Network, analytics, accounts, sync | none |

### Android permissions (release merged manifest and `aapt2 dump permissions`)

```
android.permission.RECEIVE_BOOT_COMPLETED
android.permission.VIBRATE
android.permission.POST_NOTIFICATIONS
com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION   (signature, app-private)
```

Identical to v1.0.0. Absent: INTERNET, READ/WRITE/MANAGE_EXTERNAL_STORAGE,
READ_MEDIA_IMAGES / _VIDEO, contacts, usage access, accessibility service,
camera, microphone. New components: `ShareFileProvider` and
`SharePlusPendingIntent`, both `exported="false"`. `<queries>` unchanged
(`PROCESS_TEXT`, and `GET_CONTENT` from file_picker as in v1.0.0). The
debug and profile manifests keep Flutter's development-only INTERNET entry,
as before; it is not in release builds.

## Tests

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` | **693 / 693** (635 at Phase 10A) |
| Migrations (`migration_test`, `_v3`, `_v4`, `_v5`) | 39 / 39 |
| Backup (`backup_restore`, `backup_v2_restore`, `backup_format`, `backup_v2`) | 71 / 71 |
| Phase 10A (`phase10a_flow_test`, `achievement_reconciliation_test`) | 21 / 21 |
| Phase 7 (`phase7_accessibility_test`, `phase7_lifecycle_test`) | 30 / 30 |
| Phase 10B (three new files) | 58 / 58 |
| `flutter build apk --debug` | PASS |
| `flutter build apk --release` | PASS (63.6 MB; local build, not a distribution artifact) |
| `flutter build ios --simulator` | PASS (Xcode 27 beta, local) |

New tests:

- `test/features/share_card_data_test.dart` (23): Arc kind and day;
  completed / total; Minimum Day vs Perfect Day; 12 habits in order with
  accurate status; habit names / XP & level / streak off remove those
  values from every string; honest streak names; bedtime and any clock time
  never present; no reflection or mood fields; share text without habit
  data or query strings; My Arc only enabled habits, full targets, count /
  duration / binary / clock labels, pending edit not shown, rolling vs
  seasonal wording, late join never Day 1, 12 long names; achievement
  title, criterion, unlock day, no calendar date, locked gives no card,
  reflection achievement carries no text; file-name sanitizing.
- `test/features/share_card_render_test.dart` (17): every variant (12
  habits, 12 × 40-character names, one habit, Minimum Day, seasonal,
  everything hidden, rolling / late seasonal / 12-name My Arc, every
  catalog achievement) renders a valid 1080 × 1350 PNG with no overflow;
  byte-identical export across devices, densities, text scales and chrome;
  names hidden renders no title; Minimum Day pill; My Arc full targets.
- `test/features/phase10b_flow_test.dart` (18): the full Today → choice →
  preview → Share flow with a fake gateway (one PNG, `image/png`,
  `nextrep-day-1.png`, 1080 × 1350, iPad origin, exact share text,
  only the card inside the export boundary, no Journal text on screen or in
  semantics, **database identical before and after**); privacy switches
  change the export and semantics and reset for the next preview; rapid
  taps → one request; dismissed → no message; platform failure → one
  message, no retry, Share usable again; Minimum Day card; My Arc full
  targets on a Minimum Day; achievements: locked has no tap action or sheet,
  unlocked opens details with "Share First Rep" and shares
  `nextrep-achievement-first-rep.png`; 2× text for the Today entry, choice
  sheet, Today preview, My Arc preview and achievement flow with tap-target
  and label guidelines; motion: Normal → Minimum and back transition,
  ordinary + doesn't, reduced motion immediate with no transient callbacks,
  preview reveal completes once, reduced-motion preview complete on the
  first frame and still shareable.

Existing Phase 7 reduced-motion and accessibility coverage is unchanged
and passes.

## Deferred

Not implemented in 10B:

- **Phase 10C:** Hair Care, Skin Care, Fruit, Nuts / Seeds, Mobility and
  Reading templates; expanded and activity-specific achievements;
  achievement grouping / backfill for the larger catalog.
- **v1.2:** smart water reminders; social-media usage / Focus Guard;
  `UsageStatsManager`; foreground / background usage monitoring.
- Not planned: friend accounts, couple linking, live progress sharing, QR
  pairing, leaderboards, comments, reactions, automatic posting, referral
  tracking, remote share templates.
- `PRIVACY.md` still describes 1.0.0. A "Share cards" section (user-started
  sharing through the system sheet, what a card contains and never
  contains, the cache behaviour) is due when v1.1.0 is prepared, not before.
- Physical-device qualification of the share sheet (Android and iPad) and
  TalkBack: not a merge gate for this phase; due with the v1.1.0 release
  candidate.
