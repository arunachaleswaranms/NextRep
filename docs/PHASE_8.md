# Phase 8: Store Launch & Physical Qualification

## Objective

Clear as many real-world release gates as possible without changing what
the app does. Phase 8 is qualification, not features:

- run the release build through the flows a user runs, on a device
- prepare store screenshots, signing and the forms
- record what is still blocked and who has to unblock it

Nothing was published or uploaded. No accounts, keys, certificates,
identifiers, versions or backup policies were created or changed.

**Freeze kept.** The database schema stays **v5** and backup export stays
**format 2** (it still reads format 1). No dependency changed. The only app
code changes are three small copy and large-text fixes found on the
device (below).

## Results at a glance

| Gate | Platform | Result |
|---|---|---|
| Physical Android (any gate) | physical | **MANUAL REQUIRED**: no device appeared in `adb devices` during the session |
| TalkBack | physical | **MANUAL REQUIRED** |
| Physical iPhone | physical | **MANUAL REQUIRED**: no iPhone connected (and no Apple signing; see below) |
| VoiceOver | physical | **MANUAL REQUIRED** |
| In-place upgrade, schema v5 data (Phase 7 install → Phase 8 release) | emulator | PASS |
| In-place upgrade, schema v4 data (Phase 5 release → Phase 8 release), real migration | emulator | PASS |
| Fresh install: onboarding, Arc choice, Habit Setup, custom habit, Start | emulator | PASS |
| Habit controls: binary complete/undo, rapid count +/−, duration ±, Undo snackbar | emulator | PASS |
| timeBefore: picker, pass, fail, change, clear, keyboard entry | emulator | PASS |
| Minimum Day (with a custom habit) and Perfect Day | emulator | PASS |
| Journey: 92 nodes, today, Perfect, Minimum, partial, missed, "before you joined", day detail | emulator | PASS |
| Journal: mood, keyboard, save, update the same day | emulator | PASS |
| Insights, History, Achievements | emulator | PASS |
| Notifications: deny, allow, delivery, background tap → Today, background tap → Journal, cold-start tap → Journal, OS revocation | emulator | PASS |
| Backup: export through DocumentsUI, restore with preview and confirmation, reminders off, force-stop / relaunch | emulator | PASS |
| Corrupt backups (checksum mismatch, truncated) refused, local data untouched | emulator | PASS |
| Restore on a fresh install from onboarding (192 KB, 2 arcs) | emulator | PASS |
| Text scale 2× | emulator | PASS after fix (one P2 found and fixed) |
| Remove animations | emulator | PASS |
| Landscape | emulator | usable (cramped, as recorded in Phase 7) |
| Launcher icon, notification icon, splash | emulator | PASS |
| Reboot reminder recovery | — | **MANUAL DEFERRED** |
| Profile-mode frame timing | — | **MANUAL REQUIRED** (physical only; emulator frame timing isn't meaningful) |
| Integration, emulator API 36 | emulator | 7 / 7 |
| Integration, iPhone 17 simulator (iOS 27) | simulator | 7 / 7 |

Emulator results are recorded as emulator results. None of them is counted
as a physical-device pass.

## Baseline (main `57a3c13`, PR #7 merged)

| Check | Result |
|---|---|
| Format / analyze | 0 changed / no issues |
| `flutter test` | 602 / 602 |
| Migrations v1 → v5 | 39 / 39 |
| Backup format 1 + 2 | 70 / 70 |
| Release qualification suite | 36 / 36 |
| `schemaVersion` / backup `formatVersion` | 5 / 2 |
| CI on main | green (run 37342208393) |
| Toolchain | Flutter 3.47.5, Dart 3.13.4, Xcode 27 (beta), Android SDK 36, JDK 21 for Gradle |
| Devices | AVD `RideLink_API36` (Android 16, API 36, 1280 × 2856, 480 dpi), iPhone 17 simulator (iOS 27). No physical Android, no physical iPhone |

## Decisions still pending (owner)

Asked at the start of the phase. Each was left undecided, so nothing was
changed.

| Decision | Current value | Status |
|---|---|---|
| Android `applicationId` | `com.nextrep.nextrep` | **OWNER DECISION REQUIRED** before store registration |
| iOS bundle id | `com.nextrep.nextrep` (`RunnerTests`: `.RunnerTests`) | **OWNER DECISION REQUIRED** |
| First public version | `1.0.0+1` (the scaffold value) | **OWNER DECISION REQUIRED** |
| Android system backup | `allowBackup` unset, so enabled | **OWNER DECISION REQUIRED** (options below) |
| Typography | platform fonts (Roboto / SF Pro); Manrope not bundled | kept; not a release blocker |
| iPad and phone landscape | both enabled | kept; landscape is cramped but usable |

### Android system backup: the two options

- **A. Keep it (current).** App data can survive a phone replacement
  through Android's device backup. Google's backup, which the user
  controls, can contain the local database, including reflections. This
  is already disclosed in PRIVACY.md.
- **B. `android:allowBackup="false"`.** Only an explicit NextRep export
  ever moves the data. Android device backup and device-to-device restore
  stop carrying it. Before shipping that, check whether `targetSdk` 36
  also needs `android:dataExtractionRules`, update PRIVACY.md and
  STORE_READINESS.md, and re-test install and upgrade.

## Physical Android

**MANUAL REQUIRED.** The owner chose to connect an Android device for this
session. `adb devices -l` was polled for five minutes at the start and
checked again later. Only `emulator-5554` ever appeared. Every Android gate
below was run on the API 36 emulator instead, with the **release** APK.
The physical pass is the [runbook](#physical-runbook) at the end.

## Android upgrade

The emulator already had NextRep installed (first installed 2026-10-04)
with schema v5 data: an active Seasonal arc joined on Day 4, seven habits
and one achievement. That install was a leftover `flutter test
integration_test` build: its entry point waits for a test driver, so it
stops at the splash on its own. It is not a user build, but its database
is real.

1. Row counts recorded before the upgrade (no content read).
2. `adb install -r` with the Phase 8 release APK; no data cleared.
3. Cold launch: 1.36 s (`am start -W`). Today showed Day 6 of 92,
   "Seasonal Winter Arc · joined Day 4", 15 XP and 1/15 achievements:
   the same data. The package is no longer debuggable.
4. Journey, Journal, Insights, History and reminder preferences (both
   off, as stored) all read correctly. Force-stop and relaunch kept
   everything.

**Real migration on the device:**

1. Built the Phase 5 release (`7a0ac04`, schema **v4**) in a separate
   worktree.
2. Installed it fresh and started a Rolling arc. Logged No Junk Food and
   three glasses of water, and saved a synthetic reflection.
3. Installed the Phase 8 release over it in place.
4. Cold launch in 1.79 s with no crash. Day 1 of 92, 1 of 4 done, water
   3 / 8 and 15 XP were kept; the arc is a "Rolling Winter Arc" (the v5
   default kind). The Journey, the Journal entry, History, Insights and
   reminders (off) were all intact.

**ANDROID IN-PLACE UPGRADE: PASS (emulator).** A physical upgrade from
the installed CPH2707 build is still in the runbook.

## Android core flow (emulator, release build)

- **Fresh install:**
  - onboarding, then the Arc choice (Rolling and in-season Seasonal both
    offered)
  - Habit Setup: Sleep Before Target turned on, a custom count habit
    created ("Stretch", goal 6, minimum 2)
  - Start, which opened Day 1 of 92 with 6 habits
- **Binary:** complete gives +15 XP, `checked` and an Undo snackbar; Undo
  reverts the XP.
- **Count:** six rapid taps and one decrease gave exactly 5 of 8. Duration
  steps of 5 min were correct.
- **timeBefore:**
  - 23:30 with a "before 23:30" goal counts as done
  - 00:45 counts as "After the goal" and the XP is revoked
  - Clear resets it to "not logged"
  - with the keyboard (text input mode) the dialog moves above the
    keyboard and stays fully visible
- **Minimum Day:**
  - the sheet lists every target change
  - the switch is one-way
  - the custom habit scales 6 → 2
  - the Journey reads "Day 1. Today. Minimum Day, 16 percent complete."
- **Perfect Day:** completing every habit showed the celebration (Perfect
  Day, then Clean Sweep), and the Journey reads "Day 6. Today. Perfect
  Day."
- **Journey:**
  - all 92 nodes are present and labelled (counted through the
    accessibility tree)
  - today, Perfect, partial ("Partial, 20 percent complete"), missed and
    "Before you joined this Seasonal Winter Arc" are spoken in words
  - five milestones are present
  - the day detail sheet opens and closes
- **Journal:**
  - the mood is exposed as `selected`
  - the remaining-characters counter updates
  - save, then update the same day ("Update Reflection")
- **Insights, History and Achievements** render. Day counts start from the
  join day (Days climbed: 3 for a Day 4 join on Day 6).
- **Privacy:** after the Journal and backup flows, logcat had **0** lines
  containing the synthetic reflection text.

## Notifications (emulator, release build)

| Step | Result |
|---|---|
| Reminders off by default | PASS |
| First enable asks for permission | PASS ("Allow NextRep to send you notifications?") |
| Deny | PASS. "Notifications weren't allowed, so the reminder stays off…"; the switch stays off; the app stays usable |
| Allow (second request) | PASS. The switch is `checked` |
| Scheduling | PASS. Inexact `RTC_WAKEUP` alarms (window +1 m 15 s for today, +1 h for later days), 14-day horizon |
| Daily delivery | PASS. Delivered for a 22:52 slot by 22:53, channel `daily_reminder`, visibility PRIVATE, generic text "Your Winter Arc is waiting." |
| Background tap → Today | PASS (the app was on Reminders) |
| Reflection delivery and background tap → Journal | PASS (the app was on Journey) |
| Cold-start tap → Journal | PASS. The process was killed (`am kill`) before delivery and again after it, so the tap started a new process: displayed in 1.39 s on the Journal |
| OS revocation (system Settings → All NextRep notifications off) | PASS. Both preferences stay on, "Notifications are turned off for NextRep in system settings…", no prompt |
| Restore turns reminders off | PASS. Both switches off; 0 NextRep alarms left in `dumpsys alarm` |

`am kill` was used instead of force-stop on purpose. Android's force-stop
cancels every alarm an app has (that's the OS, not NextRep), so it can't
test delivery to a stopped app.

**Reboot recovery: MANUAL DEFERRED.** The boot receiver
(`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`) is in the manifest, and the app
reconciles its reminders on launch. A reboot test belongs on the physical
device.

## Backup (emulator, release build, system DocumentsUI)

- **Export:**
  - Data & Backup, then Export Backup, then the privacy warning ("…not
    encrypted: anyone who can open it can read your Journal")
  - Choose Location, then DocumentsUI Save
  - "Backup saved." `nextrep-backup-2026-10-06.nextrep`, 3,122 bytes.
    Header `product: NextRep`, `formatVersion: 2`. Only metadata was read.
- **Restore:**
  - changed the data after the export (2 of 5 done, 45 XP)
  - picked the file; the preview showed exported time, arcs 1, active arc,
    reflections 1, achievements 2
  - "Replace current data? This device has 1 Arc and 1 reflection…"
  - Replace Data
  - Today returned to the exported state (0 of 5, water 5, 15 XP) with
    reminders off
  - force-stop and cold relaunch (1.31 s): still the restored state, with
    the reflection intact
- **Corruption** (on copies only; the original export was never changed):
  - a copy with one value edited and the old checksum: "That backup is
    damaged or was changed after it was exported… Nothing was changed."
  - a copy truncated to half: "That file isn't a NextRep backup. Nothing
    was changed."
  - the local data (1 of 5, 30 XP) was unchanged after both
- **New-device restore:** onboarding's "Restore from a backup" restored a
  192 KB file with 2 arcs and 47 reflections straight to Today.

## Accessibility

### TalkBack

**TalkBack: MANUAL REQUIRED.** TalkBack is installed on the emulator and
was turned on. But `adb shell input` events don't go through TalkBack's
touch explorer: a vertical swipe scrolled the list and a single tap
activated a control. So a gesture-level TalkBack pass (explore, swipe,
double tap) can't be scripted over adb. It needs a person, ideally on the
phone. TalkBack was turned off again, and the accessibility settings were
restored (both `null` / `0`).

What was checked without that: the node tree TalkBack reads, through
`uiautomator`, on every screen above.

- Every control has a label and is `clickable`.
- Binary habits are `checkable` and `checked`. Reminder switches expose
  `checked`. Moods and tabs expose `selected`.
- Journey days are spoken in words (above).
- Text fields expose a hint (for example `hint="Name"`).
- Destructive actions are named: "Replace Data", "Cancel setup".
- The celebration reads "…, Tap to dismiss".
- Phase 7's widget tests still cover `SemanticsAction.tap` on every custom
  button and the 56 dp Journey targets.

Two spoken-label defects found this way are fixed (below).

### Text scale

At 2× font on the emulator: Today, Journey, Journal and Data & Backup keep
every action reachable.

- The Journey header scrolls within half the screen, which Phase 7 made
  intentional, so the path stays visible.
- **Found and fixed (P2):** on Today, the level row next to the XP pill cut
  "Level 1" to "Le…" and "30 / 250 XP" to "30 / 250…". After the fix it
  reads "Level 1 15 / 250 XP" in full at 2×.

### Reduced motion

With "Remove animations" on (all three animator scales at 0):

- Today worked
- reaching a Perfect Day applied every state (5 of 5, streak, XP 120)
- the Perfect Day and Clean Sweep cards were static and dismissed with a
  tap
- the Journey showed "Today. Perfect Day."

The original settings were restored (`animator_duration_scale` unset,
transition and window 1.0).

## Defects found and fixed

| Severity | Where | Finding | Fix |
|---|---|---|---|
| P2 | Today (and the Journey header) at 2× text | "Level 1" and "30 / 250 XP" ellipsized: a `Spacer` beside two `Flexible`s gave the level a quarter of the row | `LevelBar` uses a `Wrap`: side by side when they fit, stacked at large text |
| P2 | Arc History card (screen reader) | "1 reflections", "2 achievements" (the card shows 2/15) | "1 reflection", "1 Perfect Day", "N of 15 achievements" |
| P2 | Arc choice cards (screen reader) | "…don't count against you.. In season" (doubled period) | parts that already end in a period don't get a second one |

Each fix has a regression test in `phase7_accessibility_test.dart`. All
three tests fail against the previous code and pass now. No P0 or P1 was
found.

## Performance

- Release cold launches on the emulator (`am start -W` TotalTime):
  - 1.10 to 1.54 s on a fresh install
  - 1.31 to 1.36 s on existing data
  - 1.79 s on the first launch after the v4 → v5 migration
  - 1.39 s for a notification cold start
- Scrolling all 92 Journey nodes needed no waits, and the accessibility
  tree followed every scroll.
- These are emulator observations. **No frame-timing numbers were
  measured.** A `flutter run --profile` frame check on physical hardware
  is still manual.

## Icon and splash

- **Icon:** the launcher icon is the round adaptive icon, with the peaks
  and summit light unclipped. The notification small icon is the white
  ridge glyph. The themed icon wasn't checked: it needs the launcher's
  "Themed icons" setting changed, which is left for the physical pass.
- **Splash:** a night background with the mark, and no white flash on cold
  launch.

## Store screenshots

[`tool/screenshots/generate_screenshot_backup.dart`](../tool/screenshots/generate_screenshot_backup.dart)
is a dev-only tool, like the brand-asset generator. It is not part of the
test suite or the app.

- **What it builds:** two invented arcs, made through the app's own
  services:
  - last season's late-joined Seasonal arc, finished at the summit
  - a Rolling arc on Day 20, with 3 of 6 habits done today
- **Output:** it exports them with the real backup service, to
  `build/screenshots/` (git-ignored).
- **On a test device:** restoring the file gives deterministic screenshot
  states. There is no demo code in the app, and no personal data.

All eight screenshots in [STORE_METADATA.md](STORE_METADATA.md#screenshots)
were captured from it on the emulator (release build):

- 1080 × 2160 (2:1, within Play's limit)
- demo-mode status bar at 9:30

They are kept out of git. The capture steps are in STORE_METADATA.md. No
screenshot was uploaded.

## iOS

| Gate | Result |
|---|---|
| `flutter build ios --simulator` | PASS |
| `flutter build ios --release --no-codesign` | PASS (21.1 MB `Runner.app`; bundle id `com.nextrep.nextrep`, version 1.0.0 (1), display name NextRep; unsigned) |
| Simulator integration (iPhone 17, iOS 27) | 7 / 7 |
| **IOS SIMULATOR SOFTWARE** | **PASS** |
| Physical iPhone | **MANUAL REQUIRED**: none connected. Even with one, install is **BLOCKED BY SIGNING**: no `DEVELOPMENT_TEAM` is set and no Apple signing exists |
| VoiceOver | **MANUAL REQUIRED** |
| Real iOS notifications, Files picker | **MANUAL REQUIRED** (codec and restore covered by the simulator suite) |
| **IOS PRODUCTION SIGNING** | **MANUAL REQUIRED** |

## Android signing and artifacts

`android/key.properties` doesn't exist, so release builds fall back to the
debug key, as designed. **ANDROID STORE SIGNING — MANUAL REQUIRED.** No
keystore was generated.

| Artifact | Result | Signer | SHA-256 |
|---|---|---|---|
| `app-release.apk` (63.1 MB, `7ebd644`) | PASS | `CN=Android Debug` (debug key; **QA only, not uploadable**) | `449a22a3ec8579181003b2ea3d267b712b48aa8d9a4a633f5442dcb2684a1a64` |
| `app-release.aab` (61.4 MB, `7ebd644`) | PASS | `CN=Android Debug` (**not uploadable**) | `76e574f4bc071969e596c584c46cbaf8ef01f159657f7818cf19eca12c382bcf` |

The APK reports (aapt2) package `com.nextrep.nextrep`, versionName
`1.0.0` and versionCode 1. The AAB's base manifest names the same package
and the same three permissions, and both come from one Gradle
configuration.

Debug key certificate (the same for both): `C=US, O=Android, CN=Android
Debug`, SHA-256
`53:17:21:0B:81:8A:83:8B:ED:FD:3B:06:94:04:89:F6:46:54:24:5C:22:B2:AD:38:5A:3D:D9:D6:62:F6:16:7D`.
This is the local debug keystore, not an upload key.
The hashes identify these QA builds only. They are **not** final store
candidates, because the identifier, version and upload key are all still
open.

### Release permissions (aapt2, final APK)

```
uses-permission: android.permission.RECEIVE_BOOT_COMPLETED
uses-permission: android.permission.VIBRATE
uses-permission: android.permission.POST_NOTIFICATIONS
permission:      com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

`INTERNET`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`,
`MANAGE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE` and
`WRITE_EXTERNAL_STORAGE` are all **absent**. `targetSdk` and `compileSdk`
are 36.

## Quality gates (final code)

| Gate | Result |
|---|---|
| Format / analyze | 0 changed / no issues |
| `flutter test` | **604 / 604** (602 at baseline + 2 regression tests; a third regression is an assertion in an existing test) |
| Coverage | **93.3%** of handwritten `lib` (excluding `.g.dart` and the generated `schema_versions.dart`); 91.8% including it. Unchanged from Phase 7 |
| Migrations v1 → v5 | 39 / 39 |
| Backup format 1 + 2 | 70 / 70 |
| Release qualification suite | 38 / 38 |
| Integration, emulator API 36 / iPhone 17 simulator | 7 / 7 / 7 / 7 |
| `flutter build apk --debug` / `--release` | PASS / PASS (debug-signed) |
| `flutter build appbundle --release` | PASS (debug-signed, not uploadable) |
| `flutter build ios --simulator` / `--release --no-codesign` | PASS / PASS |

## Security and privacy audit

- **Logging:** the only call in `lib/` is the documented `developer.log`
  in `error_reporter.dart`. There are no `print` or `debugPrint` calls.
- **Secret patterns:** `BEGIN PRIVATE KEY`, `storePassword=`,
  `keyPassword=`, API keys, `Bearer`, tokens and `secret` only match
  placeholders (`android/key.properties.example`, `ANDROID_SIGNING.md`), a
  CI comment and a test string.
- **Signing files:** no keystore, `key.properties`, `.p12`,
  `.mobileprovision`, `.p8` or service-account file is tracked.
- **Reflection text:** it never appeared in logcat.

## Privacy policy

[PRIVACY.md](../PRIVACY.md) still matches the app; nothing factual changed
in Phase 8. It is not published.

- **Public URL:** none.
- **Contact address:** missing.
- **Developer / publisher identity:** missing.

**PRIVACY POLICY PUBLICATION — OWNER ACTION REQUIRED.**

## Blockers

- **Software:** none. No P0 or P1.
- **Physical device:**
  - the physical Android pass (upgrade over the CPH2707 install, real
    delivery, reboot, Files / Drive backups, TalkBack, a profile frame
    check)
  - a physical iPhone and VoiceOver (also blocked by signing)
- **Owner decisions:** identifiers, the first public version, the Android
  system-backup policy.
- **Store and signing:**
  - Android upload key
  - Apple Developer team and distribution signing
  - privacy policy URL and contact
  - Play feature graphic
  - iPhone 6.9" and iPad screenshots
  - Play Data safety and App Store privacy forms

**Recommendation.** The software is a release candidate. **STORE
SUBMISSION — MANUAL GATES REMAIN.**

## Physical runbook

On the CPH2707 (USB debugging on), with the release APK of this branch:

1. `adb install -r build/app/outputs/flutter-apk/app-release.apk` over the
   existing NextRep install, without clearing data. Check that Today, the
   Journey, the Journal, Insights, History and reminders are unchanged.
   Force-stop and relaunch.
2. Repeat the [core flow](#android-core-flow-emulator-release-build),
   [notifications](#notifications-emulator-release-build) and
   [backup](#backup-emulator-release-build) steps by hand. Use Files and
   Drive as backup destinations, and use only a *copy* of a backup for the
   corruption check.
3. Schedule a reminder, reboot, and confirm that it still arrives.
4. Turn on TalkBack. Swipe through Onboarding, Arc choice, Habit Setup, Add
   Habit, Today (including timeBefore and Minimum Day), Journey, Journal,
   Insights, History, Summary, Backup and Reminders. Double-tap every
   control. Turn TalkBack off afterwards.
5. Check font size at maximum, "Remove animations" and the themed icon,
   then restore each setting.
6. `flutter run --profile -d <device>`: scroll the Journey and Today and
   note what you see in DevTools' frame chart.

On an iPhone, once signing exists: install, notifications and a tap,
export and import through Files, the bedtime picker, background / resume,
and VoiceOver on the same screens.
