# Phase 7: Release Readiness & Premium UX

## Objective

Make NextRep feel shippable without adding product scope. Phase 7 audits
the merged Phase 6 app for release, then fixes what it finds:

- polish and consistency
- accessibility, text scaling and reduced motion
- lifecycle and failure states
- branding
- the release build configuration and store documents

Every check below was actually run. Gates that need hardware or accounts
the environment doesn't have are listed as manual.

**Freeze kept.** There are no new arc kinds, habit types, XP rules,
achievements, database tables, networking or dependencies. The database
schema stays **v5**, and the backup export stays **format 2** (it still
reads format 1).

## Baseline (main `840ed50`, PR #6 merged)

| Check | Result |
|---|---|
| Format / analyze | clean / no issues |
| `flutter test` | 566 / 566 |
| Migrations v1 → v5 | 39 / 39 |
| Backup format 1 + 2 | 70 / 70 |
| Seasonal + participation / timeBefore | 42 / 17 |
| CI on main | green (run 37226322656) |
| Emulator integration | 6 / 6 (Phase 6 smoke failed once in the time picker, then passed on a clean re-run) |
| Devices | emulator-5554 (API 36), iPhone 17 simulator (iOS 27). The physical CPH2707 was **not connected** |

## Release audit

Three read-only audit passes covered:

1. UX, tokens and error copy
2. accessibility, motion and performance
3. lifecycle, reminders and backup

The architecture held up: no optimistic UI, writes are arc- and date-checked,
historical screens read by session id only, and restore is transactional.

| Area | Finding | Outcome |
|---|---|---|
| Lifecycle | No refresh at midnight while the app stays open; a tap after midnight on Day 92 left a dead Today until resume | fixed: `DayChangeTicker` and the close-out on a rejected write |
| Lifecycle | Habit Setup computed the season day with a clock read in `build` | moved into the setup view model |
| Accessibility | 13 `Semantics(button, excludeSemantics)` nodes had no tap action, so switch access, voice access and screen-reader activation did nothing | fixed: each carries `onTap` |
| Accessibility | The clock card's Clear button was hidden from screen readers | exposed as a custom action |
| Accessibility | Journey markers: the tap area was the drawn marker (26–40 dp); today read "Day 1, Today, today" | 56 dp target; state in words |
| Text scale | The Summary heading (fixed 340 px), the progress ring, day-detail rows, the mood timeline and onboarding clipped at 2×; the Journey header pushed the path off screen | fixed; covered by 2× tests |
| Errors | A deleted or unknown arc id gave "Try again" that could never succeed; unknown routes showed go_router exception text; release had Flutter's grey error box and printed framework errors to logcat | fixed |
| Reminders | A throwing permission check took the settings screen down; a scheduler failure after saving said "Something went wrong" with the switch on | fixed |
| Copy | The backup note said an *edited* file is refused; the checksum is unkeyed SHA-256 | "accidental corruption can be detected" |
| Copy | "Perfect Day: No" on a completed Minimum Day; "1 days"; empty mood bars when no mood was picked | fixed |
| Branding | The default Flutter icon, a white launch screen, "nextrep" / "Nextrep" labels | new identity |
| Privacy | `allowBackup` is unset, so Android system backup can include the database | **documented, user decision** |
| Typography | The brief names Manrope, but no font is bundled: the app uses Roboto / SF Pro | **reported, not changed** (see blockers) |

Tokens were already disciplined: no raw hex colours outside the theme and
no animation that bypasses `context.motion`. Two hand-rolled card
decorations moved to `WinterCard`; spacing literals that matched tokens use
the tokens.

## UX changes

- **Onboarding:**
  - Explains the climb (habits → XP → mountain), templates or custom habits,
    Rolling vs Seasonal, and "Everything stays on this device. No account."
  - Still one screen. The explanation scrolls; "Let's Begin" is always
    visible.
- **Arc choice:**
  - The in-season card says "Days before you join don't count against you."
  - Preseason: "Set up your habits now, then join on October 1. Day numbers
    follow the season."
  - Closed season (Jan–Aug): a calm card with a schedule icon, warm status
    text and "Not available yet" in its semantics, instead of a 50%-opacity
    "broken" card.
  - A first-time tap shows progress on the chosen card.
- **Today:**
  - The Undo snackbar stays 4 s.
  - Binary habits expose a checked state.
  - The minus button reads "Decrease {habit}".
  - The progress ring label fits at any text size.
- **Minimum Day:** its day detail shows "Minimum Day: Completed / In part"
  instead of "Perfect Day: No". The Journey says "Minimum Day, 75 percent
  complete." for today.
- **Journey:**
  - Day labels in words.
  - Whole-square touch targets.
  - The header scrolls within half the screen (large text, landscape).
  - The header card uses `WinterCard`.
  - Cached date formatting per row.
- **Journal:** the editor refreshes at midnight. A save that crosses
  midnight says "It's a new day" instead of "read-only".
- **Insights:**
  - Reflections saved without a mood show "No moods picked yet." with no
    zero bars.
  - Mood rows and the timeline scale with text.
- **History:** an intentional empty state; a failed arc card has "Try
  again".
- **Summary:**
  - The heading grows below the top buttons instead of clipping.
  - "1 day" / "N days".
- **Backup and reminders:**
  - Accurate checksum copy.
  - The export dialog uses an info icon instead of a lock.
  - A file problem vs. a picker problem get different dialog titles.
  - A saved-but-not-scheduled reminder says so.
- **Shell:**
  - A labelled `LoadingView` everywhere.
  - An `EmptyStateView`.
  - `FailureView` offers "Go home" for a missing arc and "Go back" on
    pushed screens.
  - The error icon no longer suggests a network problem.

**Journey parallax: evaluated and not added.** Physical-device profiling
wasn't available. The Journey already redraws a full-screen scene behind a
lazy path, and the brief puts performance first. It stays a Phase 8 option.

## Accessibility and reduced motion

- **Semantics:**
  - Every excluded-semantics button carries its tap action, verified with
    `SemanticsAction.tap` and `tester.semantics.tap`.
  - Availability, the clock card's custom Clear action, and Journey states
    in words:
    - "Day 15. Today. 60 percent complete."
    - "Day 24. Perfect Day."
    - "Day 31. Minimum Day completed."
    - "Day 48. Missed."
    - "Day 8. Before you joined this Seasonal Winter Arc."
  - The Insights timeline is spoken.
  - The busy primary button keeps its label.
  - The decorative scene stays excluded.
- **Celebrations:** with a screen reader or switch access on
  (`accessibleNavigation`), a card stays until dismissed.
- **Touch targets:** Today passes `androidTapTargetGuideline` and
  `labeledTapTargetGuideline`. Journey passes `labeledTapTargetGuideline`;
  its markers are 56 dp.
- **Text scale:**
  - Tested at 1.3× and 2× on onboarding, Arc choice, the Summary (a
    late-joined seasonal arc), the Minimum Day sheet, day detail and the
    Journey.
  - Earlier phases' 2× tests cover Today, Journal, History, New Arc, Backup,
    Insights and Habit Setup.
  - Scaling is never globally clamped.
- **Reduced motion:** with `disableAnimations`, these settle with no
  transient callbacks and nothing missing:
  - Today, the Perfect Day card, the seasonal Journey and Achievements
  - the Summary summit, complete on its first frame
  The ambient scene is on in these tests, so a loop that ignored reduced
  motion would time out `pumpAndSettle`.

## Performance

- **Audit:** one looping controller, the Winter scene.
  - It respects reduced motion.
  - It stops in the background, and `TickerMode` mutes it on hidden tabs
    and covered routes.
  - It is disposed correctly.
- **Changes:**
  - The aurora layer gets its own `RepaintBoundary`.
  - Journey date formatting is cached per row.
  - There was no speculative optimisation.
- **Regression tests:**
  - The Journey builds fewer than 46 of its 92 markers at launch (lazy).
  - A 60-entry past Journal builds fewer than 30 cards.
- **Release APK on the emulator:**
  - Cold launch 1.15 s (`am start -W` TotalTime); a notification cold start
    displayed in 1.68 s.
  - Smooth scrolling was checked by eye.
  - No frame-timing numbers were measured. **Physical profile run: manual.**

## Lifecycle hardening

- `DayChangeTicker` (`lib/app/day_change.dart`):
  - Owned by the app root and driven by the injected `Clock`.
  - Fires one second after each local midnight while in the foreground.
  - Re-armed on resume, so a clock or time-zone change while away is
    picked up.
  - Stopped on pause.
  - Recomputed from wall time each day, so DST never shifts it.
- On tick: the arc close-out runs, then `arcRefresh` and the new
  `dayChanged` signal. Today, Journey, Insights, History, Journal and Habit
  Setup re-read.
- A rejected Today write (e.g. `staleDay`) re-runs the entry-point
  close-out.
- **Tested with injected clocks** (the device clock is never changed):
  - midnight rollover
  - rolling Day 92 → 93 (by tick and by tap)
  - Seasonal 31 Dec → 1 Jan
  - 30 Sep → 1 Oct preseason join
  - an expired setup on 1 Jan
  - a reflection across midnight
  - a time zone that moves the start instant's date
  - EU and US DST inside the season
- **Mutation-checked:** disabling the ticker fails the four midnight tests;
  reverting the close-out fails the Day 92 tap test.

## Notifications (release build, emulator API 36)

| Check | Result |
|---|---|
| Off by default; permission asked only when a reminder is turned on | PASS. The system prompt reads "Allow NextRep to send you notifications?" |
| Denial | PASS. "Notifications weren't allowed…"; the switch stays off; the app keeps working |
| Scheduling | PASS. Inexact `RTC_WAKEUP` alarms on the plugin receiver, a 14-day horizon, no crash under R8 |
| Delivery | PASS. "How did today go?" delivered at 18:50 for an 18:47 slot (inexact window), channel `reflection_reminder`, visibility PRIVATE |
| Background tap | PASS. Opened the Journal |
| Cold-start tap | PASS. Process killed before delivery; the tap launched the activity (1.68 s) into the Journal |
| OS-revoked permission | PASS. The preferences stay on, "Notifications are turned off for NextRep in system settings…" is shown, no re-prompt |
| Restore | PASS. Reminders come back off; no app alarms left pending (`dumpsys alarm`, pending per uid) |
| Widget tests | revoked state, failing permission check, scheduler failure after save |

## Backup qualification

- **Automated:**
  - format 1 and format 2 restore, checksum mismatch, unsupported version,
    oversize, malformed files, rollback, reminders off, and the preview and
    confirmations (Phases 5–6, still green)
  - Phase 7: a failing picker isn't blamed on the file
  - the release smoke exports, restores and cold-reloads on the device
- **Release build on the emulator, through the system document UI
  (DocumentsUI):**
  - Export: the dialog opened with `nextrep-backup-2026-10-05.nextrep` and
    "Backup saved." appeared.
  - A malformed file was refused ("That file isn't a NextRep backup.
    Nothing was changed.").
  - A damaged-content file was refused ("…can't restore safely. Nothing was
    changed.").
  - The valid file showed its preview, then "Replace current data?", then
    restored and reloaded on Today, Day 5 of 92, with reminders off.
- **iOS:** the codec and restore run in the simulator integration suite. The
  Files picker on a physical iPhone is **manual**.

## Branding

`tool/brand_assets/generate_brand_assets.dart` is a dev-only script, run
with `flutter test tool/...` and never part of the test suite. It holds one
geometry: two snow peaks and a saddle (an ascent that reads as a quiet "N")
under a warm summit light, on the night sky. From that it writes:

- `assets/branding/nextrep_icon.svg` (the source of truth)
- Android adaptive background, foreground and **monochrome** (themed icon)
  vector drawables, round and legacy launcher PNGs, and the notification
  glyph (the same ridge, white on transparent)
- every iOS `AppIcon` size as **opaque RGB**: the App Store rejects alpha,
  so the script has its own small PNG encoder
- Play (512) and App Store (1024) listing icons, and the iOS launch mark

Peaks stay inside the 66 dp safe circle. The snowfield bleeds off the
edges, so every mask cuts it like a horizon (checked at 40 px and under a
circle mask; launcher-dock render on the emulator).

**Launch:** the night background with the mark. Android 12+ uses the system
splash. Before Android 12 the launch layer-list is used and `NormalTheme`
matches, so there's never a white flash. iOS uses `LaunchScreen.storyboard`.
There is no artificial delay.

**Name:** `NextRep` on Android (`android:label`) and iOS
(`CFBundleDisplayName`, `CFBundleName`).

## Android configuration

| Item | Value |
|---|---|
| applicationId / namespace | `com.nextrep.nextrep`: **PRODUCTION IDENTIFIER — USER DECISION REQUIRED** |
| minSdk / targetSdk / compileSdk | 24 / 36 / 36 (Flutter 3.47 defaults) |
| Version | `1.0.0+1` from `pubspec.yaml` |
| Shrinking | Flutter's default R8 + resource shrinking. `keep.xml` keeps the notification icon. Reminders and the picker were verified in the release build. No `--obfuscate`. |
| Signing | Release uses `android/key.properties` when present (git-ignored), else the debug key. **ANDROID STORE SIGNING — NOT YET QUALIFIED** (the current artifacts are signed by `CN=Android Debug`) |
| Release APK | builds (63.1 MB universal: 3 ABIs, the Flutter engine and AOT code; no SQLCipher) |
| AAB | builds (61.4 MB), debug-signed. **Not uploadable.** |

### Release permissions (aapt2)

| Permission | Why |
|---|---|
| `android.permission.POST_NOTIFICATIONS` | optional reminders (Android 13+), asked on enable |
| `android.permission.VIBRATE` | notifications and haptics |
| `android.permission.RECEIVE_BOOT_COMPLETED` | re-schedule reminders after a reboot |
| `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX app-private receiver permission |

`INTERNET`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`,
`MANAGE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE` and
`WRITE_EXTERNAL_STORAGE` are all **absent**. `android.permission.DUMP` in
the merged manifest is only the guard on AndroidX `ProfileInstallReceiver`;
it is not requested. CI now repeats this audit on every run.

## iOS configuration

| Item | Value |
|---|---|
| Bundle id | `com.nextrep.nextrep`: **USER DECISION REQUIRED** |
| Display name | NextRep |
| Deployment target | iOS 15.0 |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`). iPad screenshots are needed unless restricted |
| Orientations | iPhone portrait + landscape; iPad all four |
| Capabilities / entitlements | none (no push, HealthKit, background modes or tracking) |
| Info.plist privacy strings | none needed |
| Builds | `flutter build ios --simulator` PASS; `flutter build ios --release --no-codesign` PASS (21.1 MB) |
| Signing | **iOS RELEASE SIGNING — MANUAL REQUIRED** (no team or profile configured; nothing changed) |

## Privacy

[PRIVACY.md](../PRIVACY.md) states what the code does: local SQLite only,
no network, no accounts, analytics, ads, telemetry, sync, sale or AI, and
generic notification text. Backups are only exported on request, are **not
encrypted**, and the checksum is not a security feature. It also says
plainly that the **OS's own device backup** (Android Auto Backup, iCloud /
computer backups) may include app data. The README previously said
reflections are "never uploaded". That is true of NextRep itself, and now
also says so precisely.

Store preparation: [STORE_READINESS.md](STORE_READINESS.md),
[STORE_METADATA.md](STORE_METADATA.md),
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md),
[ANDROID_SIGNING.md](ANDROID_SIGNING.md), [CHANGELOG.md](../CHANGELOG.md).

## Dependencies

No packages were added, removed or upgraded.

| Package | Kind | Why |
|---|---|---|
| flutter_riverpod | runtime | state and DI |
| go_router | runtime | routing, redirects |
| drift / drift_flutter | runtime | SQLite persistence |
| intl | runtime | date formatting |
| characters | runtime | grapheme-safe text limits |
| crypto | runtime | backup checksum (SHA-256) |
| file_picker | runtime | system document UI for backups |
| flutter_local_notifications | runtime | local reminders |
| timezone | runtime | `TZDateTime` for scheduling (UTC only) |
| build_runner / drift_dev | dev | Drift code generation and schema snapshots |
| flutter_lints / flutter_test / integration_test | dev | lint and tests |

There is no networking, analytics or telemetry SDK. `http` appears in the
lockfile only as a dependency of `timezone`'s database-download tool. It is
never called, and the release build has no `INTERNET` permission.

## Logging

There is no `print` / `debugPrint` in `lib/`. All failures go through
`ErrorReporter` (`dart:developer` log): visible in debug and profile, a
no-op in release. Reflection and backup errors keep only the error type.
Release builds no longer call `FlutterError.presentError`, which printed
exception text to logcat / os_log. Notification payloads are `today` /
`journal`.

## Tests

| Suite | File | Tests |
|---|---|---|
| Day-change ticker | `test/app/day_change_test.dart` | 5 |
| Time-zone and DST edges | `test/domain/date_edges_test.dart` | 4 |
| Lifecycle and failure states | `test/features/phase7_lifecycle_test.dart` | 13 |
| Accessibility, text scale, reduced motion, lazy lists | `test/features/phase7_accessibility_test.dart` | 14 |
| Release smoke (device) | `integration_test/phase7_release_smoke_test.dart` | 1 |

Existing tests changed only their presentation expectations: the Journey
labels' new wording and the Phase 2 smoke's Minimum Day label. Every
behavioural assertion stayed. `FakeReminderScheduler` gained failure
switches.

The release smoke runs on a real SQLite file with an injected clock:

1. A fresh install opens on onboarding with nothing stored.
2. Choose Rolling.
3. Add a custom count habit and turn Sleep Before Target on.
4. Start, then log a binary habit, a count step and a bedtime.
5. Check the Journey label and save a reflection.
6. Open Insights.
7. Export a format-2 backup, change the data, then restore it through both
   confirmations.
8. A cold reload from the file shows the restored state, with reminders
   off.

The seasonal late join and the bedtime picker stay in the Phase 6 smoke.

## Results (final code)

The final counts, CI run and device results are in
[PROJECT_STATE.md](../PROJECT_STATE.md).

## Known blockers and manual gates

**Software:** none known.

**Decisions for the owner:**

1. Production identifiers (`com.nextrep.nextrep` on both platforms looks
   like the scaffold default).
2. Android system backup: keep it (data survives a phone change) or opt
   out (`allowBackup="false"`).
3. Typography: bundle Manrope (OFL font files, all text metrics change) or
   stay with platform fonts.
4. iPad support (screenshots) or iPhone only; phone landscape (works but is
   cramped on the Journey) or portrait only.
5. The first public version number.

**Manual gates:**

- Android upload key and Play App Signing
- Apple Developer signing
- a physical-iPhone pass
- a fresh physical-Android pass of this build (CPH2707 was offline)
- TalkBack and VoiceOver passes
- screenshots and the feature graphic
- a published privacy-policy URL and contact
- the store forms

## Phase 8 handoff

Phase 8 should be a **release execution** phase, not a feature phase:

1. Resolve the decisions above (identifiers first; they're permanent).
2. Set up signing on the owner's machine. Build a signed AAB and an
   archived IPA.
3. Physical-device qualification:
   - CPH2707 (or any Android 13+), and an iPhone
   - TalkBack and VoiceOver
   - notification delivery
   - Files / Drive backups
   - a profile-mode frame check of Today and the Journey
4. Capture the store screenshots. Publish the privacy policy. Run the Play
   internal-testing track and TestFlight.
5. Only then consider the deferred product ideas:
   - active-arc habit creation
   - a clock-time Minimum Day policy and bedtime trends
   - encrypted backup format 3
   - Journey parallax (profile first)
   - Manrope, if chosen
