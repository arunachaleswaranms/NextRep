# Phase 8.5: Physical Android Qualification

## Objective

Run the physical Android runbook ([PHASE_8.md](PHASE_8.md#physical-runbook))
on a real phone. Phase 8 recorded physical Android as **MANUAL REQUIRED**
because no device was connected. That record stays as it was. This document
covers the later run.

This was qualification, not a feature phase. The only app change is a
one-line screen-reader fix found on the device (below). Schema stays **v5**,
backup export stays **format 2**, and no dependency changed.

**Result: PHYSICAL ANDROID: PARTIAL.** Every functional, notification,
backup, display and performance gate passed on the phone. The human
TalkBack pass was not completed (see [TalkBack](#talkback)), so physical
Android is not marked PASS.

## Device and build

| | |
|---|---|
| Device | OnePlus CPH2707 (Nord 5), Android 16, API 36, OxygenOS `CPH2707_16.0.5.1201` |
| Display | 1272 × 2800, 560 dpi, running at 90 Hz |
| Connection | Wireless debugging (adb over TLS). No USB device appeared in `adb devices -l`. |
| Baseline | `main` at `a454230` (PR #8 merged), clean tree |
| Baseline gates | format clean, analyze clean, 604 / 604 tests |
| Build | `flutter build apk --release`: **RELEASE BUILD, QA SIGNING** (`CN=Android Debug`, no `key.properties`). Not uploadable to Play. |
| Rendering | Impeller (Vulkan) |

Dates: 7–8 October 2026. The phone was the owner's own, with an existing
NextRep install. Device identifiers, network addresses and the owner's
NextRep content are not recorded here.

## Qualification matrix

| Gate | Physical Android |
|---|---|
| Device discovery | PASS |
| In-place upgrade | PASS (same version and schema, see below) |
| Cold launch | PASS |
| Background / resume | PASS |
| Force-stop / relaunch | PASS |
| Core habit flow | PASS |
| Journey | PASS |
| Journal | PASS |
| Insights | PASS |
| Real daily reminder | PASS |
| Real reflection reminder | PASS |
| Background notification tap | PASS |
| Cold-start notification tap | PASS |
| OS permission revocation | PASS |
| Reboot recovery | PASS |
| Backup export | PASS |
| Backup restore | PASS |
| Corrupt backup refusal | PASS |
| TalkBack | **MANUAL REQUIRED** (human pass not completed; node tree checked) |
| 2× text | PASS |
| Reduced motion | PASS |
| Landscape sanity | PASS (usable; Journey cramped, as in Phase 8) |
| Icon | PASS |
| Splash | PASS |
| Notification icon | PASS |
| Profile performance | PASS |

## In-place upgrade

- **Before:** `com.nextrep.nextrep` 1.0.0 (versionCode 1), first installed
  4 Oct 2026, release build, existing data (an active Arc with progress,
  XP, achievements and a reflection), reminders off.
- **Method:** `adb install -r app-release.apk`. Nothing that clears data was
  used, and the app was not uninstalled.
- **Migration:** none was exercised on the phone. The installed build was
  already schema v5 and versionCode 1. The v1 → v5 migrations are covered
  by the migration suite and by the Phase 8 emulator upgrade from schema
  v4. This gate shows that a reinstall over real data keeps it. It is not a
  schema upgrade.
- **Data:** Today, Journey, Journal, Insights, History and the reminder
  settings were the same before and after.
- **Lifecycle:** background / resume kept the screen and state. After
  `am force-stop` and a relaunch, the state was unchanged. Cold launch
  `TotalTime` was 237–475 ms across the run.

The owner's data was exported first (see Backup) and restored at the end.
The functional tests used controlled data and the synthetic screenshot
backup (`tool/screenshots/generate_screenshot_backup.dart`).

## Core flow

| Check | Result |
|---|---|
| Binary complete / undo | +15 XP and back, with a snackbar Undo |
| Count + / − | Steps by 1. Reaching the goal awards XP, going below removes it |
| Rapid count taps | 5 taps in about 0.4 s all counted (3 → 8), with no visible fighting. Force-stop and relaunch showed the same value, so the saved state matched the screen |
| Duration + / − | ±5 min |
| Bedtime (timeBefore) | A late time (00:40 against a 23:30 goal) shows "After the goal" and stays incomplete. Changing it to 23:10 completes it (+15 XP). Clear returns it to not logged. Undo works |
| Perfect Day | Completing every habit added the bonus. Undo removed it ("Perfect Day bonus removed") |
| Minimum Day | Targets dropped (30 → 10 min, 8 → 3 glasses, …). The bedtime goal stayed "before 23:30". Wording: "Today can be smaller.", "Keep moving." No shaming wording. Completing it unlocked "Adaptable" and showed 100% without Perfect Day credit |
| Sheets, keyboard, bottom nav | The time picker's keyboard mode moves above the keyboard. Sheets close with Back. All tabs route |
| Journey | Days 1–92 scrolled end to end. Perfect, Minimum Day, partial, missed, Today and upcoming states all showed. A missed day's detail sheet showed "0 / 6, 0%, Missed". On a Seasonal Arc, Days 1–14 showed as "Before you joined… not counted against you". No clipped markers or overflow |
| Journal | Mood, typing with live counters, keyboard resize, save, same-day edit, past entries read-only |
| Insights | Metrics, habit cards and the mood chart, each with numeric text |
| History / Summary | Rolling (active) and Seasonal 2025 (completed, "Joined Day 15") cards. The Summary showed its stats, View Journey, View Journal and Achievements. Delete Arc asks to confirm (cancelled) |

Haptics: the app calls them on completion and the phone vibrates, but
vibration can't be captured over adb, so it wasn't independently measured.

## Notifications

Every reminder below was NextRep's own scheduled local notification, set
through the Reminders screen. No `cmd notification` injection was used and
the clock wasn't changed. The phone schedules NextRep's inexact alarms with
a delivery window, so the delay is within Android's allowed window.

| Test | Scheduled | Delivered | Result |
|---|---|---|---|
| Daily reminder, app in background | 00:21 | 00:22:01 | Tap opened **Today** (the app had been left on Reminders) |
| Reflection reminder, app in background | 00:28 | 00:30:08 | Tap opened **Journal** |
| Reflection reminder, process killed before delivery | 00:36 | 00:37:13 | Tap cold-launched NextRep (`Displayed +316 ms`) straight into **Journal**, with no splash crash and no stale route |
| Daily reminder after a reboot, app not opened | 01:42 | 01:43:27 | The tap cold-launched into **Today** with data intact |

- **Cold start method:** `am kill` after backgrounding, not `am
  force-stop`. A force-stop puts the package in the stopped state and
  Android then drops its alarms until the app is opened, so that wouldn't
  test the cold-start tap. `stopped=false` was checked before delivery.
- **Denial:** after the OS revocation, enabling a reminder showed the
  Android prompt. "Don't allow" left the switch off with an explanation.
  Tapping again didn't prompt again. The rest of the app stayed usable.
- **Allow:** after NextRep's data was cleared (TalkBack setup, below), the
  prompt came back. "Allow" turned the switch on and scheduled the alarms.
- **OS revocation:** turning Notifications off in Android Settings (which
  ends the app's process) left the preference stored. Reminders showed
  "Notifications are turned off for NextRep in system settings, so
  reminders can't appear." Turning them back on and returning cleared the
  notice.
- **Reboot recovery:** about a minute after boot, without the app being
  opened, NextRep's boot receiver re-queued the 01:42 alarm (`dumpsys
  alarm`), and the notification was delivered on time.
- **Restore:** a restore turned both reminders off and left 0 NextRep alarms
  queued.

**Device notes (not app defects).** The phone was on Do Not Disturb
(priority) for this run. Two things filtered NextRep's notifications:

- A third-party focus app on the phone (Regain) blocked the first test
  notification (00:09) until the owner allow-listed NextRep.
- OxygenOS Do Not Disturb filters the "reminder" category. With "Allow in
  Do Not Disturb" on for NextRep, notifications came through as a priority
  app. After the reboot, that exemption wasn't applied and the notification
  was intercepted (`!allowReminders`). It was still posted to the shade,
  without sound or a heads-up.

Users on OEM focus or DND setups may need to allow NextRep.

## Backup

| Check | Result |
|---|---|
| Export | Privacy warning ("not encrypted"). Android DocumentsUI opened in Downloads with `nextrep-backup-2026-10-07.nextrep` suggested and accepted. 3,465 bytes. The app's own codec (`BackupCodec.decode` + `BackupValidator`) validated it: checksum OK, format 2 |
| Restore | Through the real picker: preview (Arcs, completed Arcs, active Arc dates, reflections, achievements), a "replaces, can't merge" warning, then a second confirmation naming what will be lost ("This device has 2 Arcs and 47 reflections…"). The original state came back, survived force-stop / relaunch, and reminders were off |
| Corrupt copy | A copy with one byte changed (a habit target 30 → 31, checksum not recomputed) was refused with "Can't use this file": "That backup is damaged or was changed after it was exported, so it can't be restored safely. Nothing was changed." The data and current Arc were unchanged |
| Original backup | Never modified. Its SHA-256 on the phone matched the pulled copy before and after. The corrupt copy and the synthetic file were deleted from the phone afterwards |
| Drive | Not tested (avoids touching the owner's account) |

## TalkBack

**MANUAL REQUIRED.** TalkBack was turned on and the owner started the pass,
completing onboarding, Arc choice and habit setup into a new Arc. The owner
then stopped before the rest of the checklist. adb input can't drive
TalkBack's gestures, so TalkBack is **not** marked PASS.

As supplementary evidence only, the accessibility node tree that TalkBack
reads was dumped with `uiautomator` on the phone, screen by screen. It
showed no unlabelled actions and no doubled periods on:

- Today (top, middle and bottom): "Achievements, 12 of 15 unlocked",
  "Level 8, 185 of 250 XP to level 9", "Complete No Junk Food",
  "Add to Workout", "Tab 1 of 4"
- the Minimum Day sheet
- Journey: every state is said in words ("Day 4. Minimum Day completed.",
  "Day 10. Missed.", "Day 18. Partial, 16 percent complete.",
  "Day 20. Today. 50 percent complete.", "Day 23. Upcoming.")
- Journal
- History: "12 of 15 achievements, 11 reflections" and, on a one-reflection
  Arc, "**1 reflection**"
- Insights: charts have text ("Excellent: 16", "Workout: 91% done. 90 of
  98 days")
- the Seasonal Summary, the Delete Arc dialog, Data & Backup, both restore
  dialogs and Reminders (switches checkable and labelled)

One issue was found and fixed. The bedtime card said "not logged" twice:
"Sleep Before Target, not logged, goal before 23:30, **Not logged**, …".
It now says it once.

## Large text (font scale 2.0)

Today, Journey, Journal, History, Data & Backup and the export dialog were
checked at 2.0. Text wraps without clipping, and every action stayed
reachable. **The level / XP row is fully readable: "Level 8" and
"230 / 250 XP"**, with XP wrapping to a second line, never cut. One
cosmetic note (P2, not fixed): the export dialog's "Choose Location"
button wraps to two lines and fills its button tightly. It stays readable
and tappable. The font scale was restored to 1.0.

## Reduced motion

Android's three animator scales were set to 0 (OxygenOS has no separate
"Remove animations" key). Today, completion and undo, the streak and the
snackbar, Journey and the Seasonal Summary all showed their final state
straight away. Nothing was missing and nothing waited on an animation.
Restored to 1.0 / 1.0 / 1.0.

## Landscape

Today, Journal and Insights in landscape are **usable**: rows reflow and
controls stay reachable. Journey is cramped (the header takes about half
the height) but scrolls and works, as Phase 8 recorded. **Not release
blocking.** Rotation was restored to portrait with auto-rotate off.

## Icon, splash and notification icon

- **Launcher:** the phone uses themed icons. NextRep shows its monochrome
  mountain-and-moon mark centred in the circular mask, undistorted. The
  full-colour adaptive and round icons were checked in the APK resources.
  The launcher theme wasn't changed.
- **Splash:** frames captured during a cold launch show the window opening
  from the icon on the dark navy night background, with no white flash.
  The app had drawn within about 150 ms.
- **Notification icon:** OxygenOS shows the app's full-colour icon in the
  status bar and shade, where it's clear and recognisable. The monochrome
  `ic_stat_reminder` (white only, alpha silhouette) is what stock Android
  uses, and Phase 8 checked it on the emulator.

## Performance (`flutter run --profile` on the phone)

Frame times came from the VM service timeline (`Animator::BeginFrame` on
the UI thread, `GPURasterizer::Draw` on the raster thread). The display ran
at 90 Hz, so the budget is 11.1 ms.

| Scenario | Frames | UI avg / p99 / max | Raster avg / p99 / max | Over 11.1 ms | Over 16.7 ms |
|---|---|---|---|---|---|
| Journey: three full scrolls up and down the 92 days | 368 | 1.6 / 2.8 / 6.7 ms | 7.7 / 10.3 / 11.0 ms | 0 | 0 |
| Today: scrolling plus complete / undo | 383 | 1.5 / 2.7 / 3.3 ms | 7.2 / 9.5 / 10.4 ms | 0 | 0 |
| Journal, Insights, History, Summary (route pushes and scrolls) | 357 | 1.6 / 5.2 / 11.3 ms | 4.5 / 9.9 / 13.5 ms | 1 UI, 2 raster | 0 |

The Journey was visually smooth on the phone, with no sustained jank during
repeated full-path scrolling. The only frames over budget were three single
frames on first route pushes. No animation kept running.

## Log privacy

During the Journal and backup steps, NextRep's own logcat lines (`--pid`)
were searched for the typed marker strings, backup JSON keys and
password / token / secret / key patterns. None were found. The release
build logs no Flutter output. The only line containing a marker came from
`adbd` echoing the test's own `adb shell input text` command, not from
NextRep.

## Device settings changed and restored

| Setting | Original | During the test | Final |
|---|---|---|---|
| Font scale | 1.0 | 2.0 | 1.0 |
| Animator / transition / window scales | 1.0 / 1.0 / 1.0 | 0 / 0 / 0 | 1.0 / 1.0 / 1.0 |
| Orientation | portrait, auto-rotate off | locked landscape | portrait, auto-rotate off (verified at the time) |
| TalkBack | off | on | off (`enabled_accessibility_services` null, `accessibility_enabled` 0) |
| NextRep notification permission | granted (user set) | revoked and denied, then re-granted | granted (user set) |
| NextRep "Allow in Do Not Disturb" | off | on | off |
| NextRep data | owner's data | test data | owner's data, restored from its backup and checked |
| NextRep reminders | off, 07:30 / 21:15 | various test times | off, 07:30 / 21:15 |
| NextRep build | 1.0.0+1 release | profile build, then release builds | final release build of this branch |

The owner turned Do Not Disturb on and allow-listed NextRep in a
third-party focus app themselves. Both were left as the owner chose. One
reboot was done for the reboot test. Battery optimisation, developer
options, display size, accounts and other apps' settings weren't changed.

## Defects

| Severity | Issue | Status |
|---|---|---|
| P0 | none | |
| P1 | none | |
| P2 | Bedtime card's screen-reader label said "not logged" twice | **Fixed** (`time_before_tile.dart`), with a regression test in `phase7_accessibility_test.dart` that failed before the fix |
| P2 | At 2× text, "Choose Location" in the export dialog wraps tightly in its button | Recorded, not changed |

## Quality gates (final code)

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean |
| `flutter analyze` | no issues |
| `flutter test` | **605 / 605** (604 + 1 regression test) |
| `flutter test --coverage` | 93.3% of handwritten `lib` (91.8% including `schema_versions.dart`). `time_before_tile.dart` 100% |
| `flutter build apk --release` | PASS, `CN=Android Debug` (QA signing), SHA-256 `4e372f520d179a3c7dcb41768cccef6cf39e59be7a2ca84e307482986d15794d` |
| Final APK on the phone | Installed in place over the owner's restored data: cold launch, data intact, no crash |

### Release permissions (aapt2, final APK)

`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, and the
app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

| Permission | |
|---|---|
| INTERNET | ABSENT |
| SCHEDULE_EXACT_ALARM | ABSENT |
| USE_EXACT_ALARM | ABSENT |
| MANAGE_EXTERNAL_STORAGE | ABSENT |
| READ_EXTERNAL_STORAGE | ABSENT |
| WRITE_EXTERNAL_STORAGE | ABSENT |

## Remaining

- **TalkBack:** a human gesture pass on the phone for the checklist above.
  Onboarding, Arc choice and habit setup were started.
- Everything in [PROJECT_STATE.md](../PROJECT_STATE.md#remaining-store-actions)
  that needs the owner: identifiers, the first version, the backup policy,
  the upload key, iOS signing and a physical iPhone (VoiceOver), the
  privacy policy and the store forms.
