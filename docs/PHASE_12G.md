# Phase 12G: Completion Sounds

## Objective and boundary

The sixth v1.3.0 user-facing feature: a short, original, fully offline
sound when a saved habit action completes a habit, a Perfect Day variant,
three selectable sets, device silent-mode compliance, and a Sound &
Feedback settings screen. Built on the approved
[ARC_CONTROL_SPEC.md](ARC_CONTROL_SPEC.md) § 8, § 9.12 and § 10 (N1–N7),
[PHASE_12A_ADDENDUM.md](PHASE_12A_ADDENDUM.md) AD14, AD15, AD17 and § L5,
the accessibility criteria of
[ARC_MOMENTUM_SPEC.md § 8.5](ARC_MOMENTUM_SPEC.md#85-acceptance-criteria),
and the feedback storage of [PHASE_12E1.md](PHASE_12E1.md).

No schema, migration, backup format, validation, dependency, permission,
network, analytics, notification channel, version or application-id
change. No XP, streak, Perfect Day, Minimum Day, level or achievement rule
change; haptics unchanged. Focus Guard's native code and channel are
unchanged. Version `1.2.0+3`; no release, no tag, no physical phone, no
production signing. No 12H hardening or 12I release work.

**Artistic acceptance of the sounds is pending the owner's Gate G
listening review.** Nothing in this document, and no automated test,
claims the owner has heard or approved them.

## Verified baseline

| | |
|---|---|
| PR #29 (Phase 12F) | **merged** 23 Nov 2026 04:06 UTC; final head `c76dc7b7f9de037062bf4cf44283db8f55e95021`; merge commit `a9e5607` |
| `origin/main` | `a9e5607ef1dd30c606b6422c608c2583f3d9cdf5`, "Phase 12F: Restart and Optional Arc Deletion (#29)" |
| Post-merge CI | run [45109820746](https://github.com/arunachaleswaranms/NextRep/actions/runs/45109820746) on `a9e5607`: **success**, both jobs ("Format, analyze and test"; "Android builds and permission audit") |
| Open PRs | none |
| Release | v1.2.0 is the latest published release |
| Invariants | package `com.nextrep.nextrep`; version `1.2.0+3`; `AppDatabase.schemaVersion` 7; backup writes format 4, reads 1–4; release permissions = the CI audit's expected set |
| Worktrees | the primary checkout and the 12 phase worktrees were clean and were not touched |
| Worktree | `~/labs/NextRep-12G`, branch `phase/12g-v1.3-completion-sounds` from `a9e5607` |

`PROJECT_STATE.md` still described PR #29 as awaiting the owner's merge;
it is corrected here from the PR's merge record.

## Sound assets

### Source and reproducibility

All six files are computed by
[`tool/sounds/generate_completion_sounds.dart`](../tool/sounds/generate_completion_sounds.dart)
from sine partials and envelopes. No recording, sample, sound library,
game or film sound, or third-party melody is used; the figures are plain
major-chord arpeggios and a rising fifth. The script needs only the Dart
SDK.

```
dart run tool/sounds/generate_completion_sounds.dart          # (re)write assets/sounds/
dart run tool/sounds/generate_completion_sounds.dart --check  # verify the committed files
```

`--check` regenerates in memory and compares with the committed files:
headers byte for byte and every sample within 1 LSB (libm's last-bit
differences between platforms can move a rounded sample by one step).
CI runs it on every push ("Completion sounds reproduce from their
source"). The sounds are released with the repository under the MIT
license.

### Recipes

| Set | Sound | Notes | Timbre |
|---|---|---|---|
| Ice Crystal (default) | habit | A6 | glass: fundamental, a 1.004× detuned copy (shimmer) and an inharmonic 2.76× partial, decays 45–130 ms |
| | Perfect Day | A5 → C♯6 → E6 at 0 / 150 / 300 ms, the last ringing 2.4× longer | the same |
| Summit Spark | habit | D5 → A5 (a rising fifth) at 0 / 110 ms | plucked string: harmonics 1–6 at 1/n, higher ones decaying faster |
| | Perfect Day | D5 → A5 → D6 → F♯6 at 0 / 100 / 200 / 300 ms | the same, brighter by register |
| Warm Ember | habit | G4 | soft mallet on a wooden bar: 1 : 2 : 4 : 10 partials, a quick contact partial |
| | Perfect Day | G4 → B4 → D5 → soft G5 at 0 / 140 / 280 / 420 ms | the same |

Every file: 6 ms raised-cosine attack per note, 45 ms raised-cosine
release to exactly zero at the end, peak-normalised to −5 dBFS,
band-limited (no partial above 7 kHz).

### Files

16-bit PCM WAV, mono, 16 kHz, canonical 44-byte header. WAV is the one
format both Android's `SoundPool` and iOS's `AVAudioPlayer` decode with no
encoder (whose output varies by platform and version) and no priming
silence. 16 kHz keeps the six files at 125,064 bytes.

| File | Length | Size | Peak | RMS | SHA-256 |
|---|---|---|---|---|---|
| `ice_crystal_habit.wav` | 350 ms | 11,244 B | −5.0 dBFS | −19.0 dBFS | `7724bcd7ad81e51f…` |
| `ice_crystal_perfect_day.wav` | 900 ms | 28,844 B | −5.0 dBFS | −18.3 dBFS | `0d026acd8136348f…` |
| `summit_spark_habit.wav` | 450 ms | 14,444 B | −5.0 dBFS | −18.0 dBFS | `d414ec7e8e370317…` |
| `summit_spark_perfect_day.wav` | 900 ms | 28,844 B | −5.0 dBFS | −18.3 dBFS | `4e8c96f46128bf6d…` |
| `warm_ember_habit.wav` | 400 ms | 12,844 B | −5.0 dBFS | −15.3 dBFS | `209a8d483b05e5e0…` |
| `warm_ember_perfect_day.wav` | 900 ms | 28,844 B | −5.0 dBFS | −14.9 dBFS | `b57e59127dbebd91…` |
| **Total** | | **125,064 B** | | | |

`test/assets/completion_sound_assets_test.dart` (38 tests) checks the
committed bytes: format and header, the lengths above and under 1 s,
peak −5 dBFS with no clipping, first and last sample zero and the first
and last 1 ms below −25 dBFS (fades, no click), no sample-to-sample jump
near full scale, audible within 10 ms and still sounding in the last
60 ms (no silent padding), no DC offset, exactly six files all declared in
`pubspec.yaml`, total under 150 KB. In the release APK the files are
stored uncompressed (required by `openFd`); CI checks that too.

## Architecture

```
TodayScreen._perform(habit, action)
  requestedAt = feedback.now()            (monotonic)
  await TodayController.perform  ──► one Drift commit (unchanged)
  ActionSuccess:
    ledger.habitAwardFor(habit) != null       ┐ the existing haptic hook
    && transition.becameCompleted             ┘ (haptic unchanged, independent)
      └─► unawaited(CompletionFeedback.habitCompleted(session, date, habit,
                     perfectDay: ledger.perfectDayGranted, requestedAt))
            reads feedback_preferences (never writes)
            off → nothing; > 1 s after the tap → nothing (never late)
            Perfect Day not yet played for (arc, date) → perfectDay, else habit
            per-habit 3 s, global 500 ms / still playing → dropped
            unawaited(SoundPlayer.play(theme, sound))  ─ errors swallowed
                     │
NativeSoundPlayer ── MethodChannel com.nextrep.nextrep/completion_sound
   Android: CompletionSoundChannel → CompletionSounds → SoundPoolEngine
   iOS:     CompletionSoundPlayer (AppDelegate.swift) → AVAudioPlayer
```

| File | Role |
|---|---|
| `lib/domain/feedback/completion_sound.dart` | **New.** `CompletionSound` (habit / Perfect Day; asset paths, lengths, channel ids); the `SoundPlayer` interface; `SilentSoundPlayer` |
| `lib/domain/feedback/completion_feedback.dart` | **New.** `CompletionFeedback`: the trigger decision and throttle; `SoundOutcome`; `MonotonicClock` (`processElapsed`, a process stopwatch) |
| `lib/data/native_sound_player.dart` | **New.** `NativeSoundPlayer` over the channel (`prepare`, `play`) |
| `lib/app/dependencies.dart`, `lib/main.dart` | `feedbackPreferencesRepositoryProvider`, `soundPlayerProvider` (silent unless `main.dart` overrides it on Android and iOS), `monotonicClockProvider`, `completionFeedbackProvider` |
| `lib/features/today/today_screen.dart` | The trigger in `_perform`; sounds warmed up on open; the entry point; `_TodayHeader` (below) |
| `lib/features/sound/` | **New.** `SoundSettingsScreen`, `SoundSettingsController`, `SoundCopy`, `SoundSettingsButton` |
| `lib/app/router/app_router.dart` | `/settings/sound` (root navigator, every state, no redirect) |
| `lib/features/habit_setup/saved_setup_screen.dart`, `lib/features/history/arc_history_screen.dart`, `lib/features/about/about_screen.dart` | Entry points |
| `android/.../sound/CompletionSounds.kt` | **New.** The player's logic, free of Android classes: load once, play only loaded sounds, `SoundPolicy` silence rule, release, stale-callback guard; `SoundEngine` and `DeviceSoundState` interfaces |
| `android/.../sound/CompletionSoundChannel.kt` | **New.** The channel; `SoundPoolEngine`; `AndroidDeviceSoundState` |
| `android/.../MainActivity.kt` | Creates the sound channel beside Focus Guard's and disposes it in `cleanUpFlutterEngine` |
| `ios/Runner/AppDelegate.swift` | `CompletionSoundPlayer`, registered after `GeneratedPluginRegistrant` |
| `pubspec.yaml` | Declares `assets/sounds/` (no dependency) |
| `tool/sounds/generate_completion_sounds.dart`, `assets/sounds/` | **New.** The source and the six files |
| `.github/workflows/flutter-ci.yml` | A named Phase 12G step; the reproducibility check; an artifact of the six files for listening; the uncompressed-storage check of the release APK |

The existing `SoundTheme`, `FeedbackPreferences`,
`DriftFeedbackPreferencesRepository`, `feedback_preferences` table and
backup format-4 field are reused unchanged. No table, column, migration
or persisted enum name was added.

## Trigger and throttle rules

A sound is requested only from `TodayScreen._perform`, after the commit
returned `ActionSuccess`, and only when **both** the commit's ledger
granted this habit's completion award (the confirmed hook of spec § 8.1,
the same one the habit haptic uses) **and** the saved transition went
from not complete to complete. Minimum Day activation, return to full
targets, habit edits, refreshes, launch, midnight, restore, achievement
backfill and celebrations never call the engine.

| Event | Sound | Covered by |
|---|---|---|
| Binary habit becomes complete | habit | W flow 1 |
| Count step below target | none | W flow 1; emulator control capture |
| Count / duration reaches target | habit | W flow 1 |
| Clock time at or before / after the goal | habit / none | W flow 1 |
| Undo, decrement, clear time, snackbar Undo | none | W flows 2, 3 |
| Completion restored after a reversal | habit, if the 3 s per-habit window allows | W flow 2 |
| The completion that makes today a Perfect Day | Perfect Day only | W flow 1; emulator t8 |
| Switching to / from Minimum Day | none | W flow 5 |
| Completing the last habit of a Minimum Day | habit (a completed Minimum Day is not a Perfect Day) | W flows 5, 6 |
| Level-up, achievement | none (their cards keep their haptics) | W flow 1, regression |
| Launch, resume, midnight, restore | none | W flow 8; settings restore tests; emulator t14, t15 |

Engine rules (`CompletionFeedback`, unit tests in
`test/domain/completion_feedback_test.dart`):

- **Global:** no sound starts within 500 ms of the previous one, nor while
  the previous one is still playing (its file length, e.g. 900 ms for a
  Perfect Day). So two sounds never overlap.
- **Per habit:** at most one sound per habit (keyed by Arc and habit) per
  3 s. A dropped repeat does not extend the window.
- **Dropped, never queued:** a throttled request returns at once; nothing
  is retried.
- **Never late:** a request whose save finished more than 1 s after the
  tap is dropped (a busy queue never produces a late sound).
- **Perfect Day:** played instead of the habit sound the first time a date
  of an Arc becomes perfect in this app process; a Perfect Day undone and
  redone plays the habit sound. A throttled Perfect Day sound is not
  counted as played.
- **Monotonic time only:** the throttle never reads the wall clock, so a
  date or time change can't reopen a window (tested with a wall-clock
  rollback through the providers).
- **State:** in memory only, one engine per process. It does not follow
  the app epoch, so a restore can't reset the throttle or the Perfect Day
  memory. Nothing is stored; no column was added.
- **Off:** the setting is read from storage on every request (so a
  changed or restored setting applies at once); off means the player is
  never asked to play or even to load.
- **Never in the way:** the engine is never awaited by the action; a
  failing setting read, a missing native side, a throwing or hanging
  player change nothing (each tested). It never writes, awards or
  touches XP, achievements or the Arc (static test).

## Platform behaviour

### Android

`SoundPool` with `USAGE_ASSISTANCE_SONIFICATION` /
`CONTENT_TYPE_SONIFICATION` and one stream. `SoundPool` requests no audio
focus. The sounds are loaded once from the APK's Flutter assets (paths are
checked against `assets/sounds/[a-z_]+.wav`; nothing else is opened) and
released when the Flutter engine is cleaned up; a load callback from a
released pool is ignored; a request before loading finishes is skipped,
never queued.

**Explicit silence rule** (`SoundPolicy`, a decision for Gate G): before
playing, the player reads `AudioManager.getRingerMode()` and
`NotificationManager.getCurrentInterruptionFilter()` (no permission
needed) and plays only when the ringer is normal **and** the filter is
"all". Silent, vibrate, every Do Not Disturb mode and an unreadable or
unknown state stay silent. The sonification stream is ringer-muted as
well, but this makes the copy ("They stay quiet on silent and Do Not
Disturb") true on every manufacturer, including one that maps the stream
differently, and testable on the JVM.

### iOS

`AVAudioPlayer` per file, ambient audio session (respects the silent
switch, mixes with other audio), registered as an in-app plugin after
`GeneratedPluginRegistrant` (the notification plugin's setup is
unchanged). Not released.

## Settings and persistence

Sound & Feedback (`/settings/sound`, § 9.12): a **Completion sounds**
switch ("A short sound when you complete a habit."), the **SOUND** radio
group (Ice Crystal, Summit Spark, Warm Ember), a Play button per set
(announced "Play Ice Crystal" …), and the help line "Sounds follow your
phone's sound settings. They stay quiet on silent and Do Not Disturb."

- Each change is written at once and the row read back; the screen shows
  only stored values. A failed write shows "Couldn't save." and the
  stored value.
- Choosing a set stores it, then previews its habit sound. A preview
  plays through the engine (never while sounds are off; it shares the
  global throttle); a preview that can't play is silent and changes
  nothing.
- Off: the list and previews are shown dimmed and disabled, with "Turn on
  sounds to choose one."
- No volume slider, no haptics switch.
- Entry points: Today (beside Reminders, active and paused), the
  saved-setup hub (after Reminders), Arc History (tab and standalone
  headers), and About (a SETTINGS row). Works with an active, paused,
  saved, finished or no Arc.
- App-level: survives relaunch and Restart (tested). A format-4 backup
  restores the stored row; formats 1–3 keep the device's setting (tested
  through the real Data & Backup flow with the genuine format-1 and
  format-2 fixtures and a format-3 rewrite); a restore plays nothing.

### Today's header

Adding the button beside Reminders made the header's five actions too wide
for its "WINTER ARC" eyebrow: on the emulator at 360 dp the eyebrow broke
inside the word ("WINT / ER / ARC" at 1×; "WI / NT / ER / AR / C" at 2×),
and the 11E / 12E2 layout sweeps reported overflows at 2× / 360 dp and
1.5× / 320 dp. `_TodayHeader` now lays the eyebrow and the actions on one
line when they fit and otherwise puts the actions on a row under the
eyebrow (wrapping, never overflowing). Confirmed on the emulator at 360 dp
at 1× and 2×; on a 411 dp phone at 1× the buttons also sit under the
eyebrow. This changes Today's layout and is listed for Gate G.

## Tests

| Layer | File | Tests |
|---|---|---|
| U | `test/domain/completion_feedback_test.dart` | 23: global 500 ms and still-playing gaps, per-habit 3 s, dropped-not-queued, simultaneous requests, a 200-tap burst, Perfect Day replacement and per-Arc/date memory, throttled Perfect Day, sound off, latency, unreadable setting, failing and hanging player, warm-up, preview, wall-clock rollback and restore through the providers |
| W | `test/features/completion_sound_flow_test.dart` | 8: every § 8.1 row through the real Today screen, commit and ledger, with haptics recorded |
| W / R | `test/features/sound_settings_test.dart` | 22: wording and defaults, choose and preview, off disables with a reason, failed write, relaunch and Restart, format-4 restore and formats 1–3 through Data & Backup, entry points in five app states, six layouts (360×800 at 1× and 2×, 320×568 at 1.5×, landscape at 1.3× and 1×, tablet), `meetsGuideline` tap target / label / contrast at 1× and 2× |
| W | `test/features/completion_sound_regression_test.dart` | 1: the same session with sounds on, off, and a failing player stores identical rows in every table but `feedback_preferences` |
| S | `test/app/completion_sound_boundary_test.dart` | 6: unique channel names; SoundPool, sonification, one stream, no focus or other player; no channel, permission or network; iOS ambient; only Today and the settings screen use the engine; bundled only |
| A | `test/assets/completion_sound_assets_test.dart` | 38 (above) |
| J | `android/app/src/test/.../sound/CompletionSoundsTest.kt` | 16: loading once, bundled paths only, play when loaded, skip before loading and never later, unknown sound, failed load retried, missing asset, silent and vibrate, every DND filter, unreadable state, policy table, playback failures, release, late callbacks, fresh engine after release, no channel collision with Focus Guard |

`test/app/network_boundary_test.dart` is unchanged and passes.

Totals on the final local run: **2,282 Flutter tests pass** (98 new),
**87 JVM tests pass** (16 new); `dart format` and `flutter analyze`
clean. The existing layout sweeps (11E, 12E2) found the header defect
above and pass after the fix.

**Mutation check:** four mutations, each run against the engine and flow
tests, each detected: ignoring "off"; removing the per-habit throttle;
never choosing the Perfect Day sound; sounding on every saved action.

## Emulator qualification

Disposable AVD `NextRep12G_API36` (API 36 `google_apis` arm64, Pixel 7,
port 5556), created for this phase and deleted afterwards; the debug build
of this branch, then its R8 release build (debug-signed in the worktree,
which has no signing key). Airplane mode was on from the music test
onwards.

### Capture method

`SoundPool.play()` succeeding was never taken as proof of sound. The
emulator's **actual mixed audio output** was recorded through its gRPC
`EmulatorController.streamAudio` (started with `-grpc 8554`), called with
`curl --http2-prior-knowledge` and a hand-encoded `AudioFormat` (48 kHz,
S16, mono, real-time); the stream was decoded to WAV and analysed in
10 ms windows (audible = RMS above −50 dBFS) and, with music, per band
(Goertzel at the music's chord tones and at the sound's 1.76 kHz
fundamental). Each trial recorded 5 s and tapped 1.5 s in. The debug
build's log line (`NextRepSound: play <id>: <result>`, debug builds only)
and Android's own records (`dumpsys audio` players, events and focus
stack) were checked beside it.

Limitations: the stream is what the emulator's virtual audio device
produced, not a phone speaker or headphones; in real-time mode it carries
packets only while the device makes sound (so "0 packets" means nothing
at all was produced, not even the touch click); levels depend on the
emulator's default volumes. The QEMU `-audio wav` backend was tried first
and produced no file on emulator 37.1.11. The gRPC port is unauthenticated
on all interfaces while the emulator runs; it held only synthetic data.

### Results

The 10 ms blip at the start of most captures is Android's touch click
(Flutter plays it on taps; "Touch sounds" is on), confirmed by the control.

| # | Condition | App result | Captured output |
|---|---|---|---|
| t1 | Ringer normal, binary completion | `iceCrystal.habit: PLAYED` | sound 0.14–0.44 s (300 ms above −50 dBFS), peak −10.3 dBFS, no clipping |
| ctl | Count step below target | no call | touch click only |
| t2 | Silent | `SILENCED_BY_RINGER` | **0 packets**: nothing produced |
| t3 | Vibrate | `SILENCED_BY_RINGER` | **0 packets** |
| t4 | Normal again | `PLAYED` | 330 ms |
| t5 | DND priority / alarms only / total silence | `SILENCED_BY_RINGER` ¹ | **0 packets** each |
| t6 | DND off | `PLAYED` | 340 ms |
| t7 | Music (Chrome, `USAGE_MEDIA`, holds focus `GAIN`) | `PLAYED` | sound 1.90–2.25 s at −16 dB in its band; music band −47.8 dB before, −47.5 dB during, −47.8 dB after: **not ducked or paused**; Chrome keeps focus (`loss: none`); NextRep made **no** focus request |
| t8 | The completion making a Perfect Day | `iceCrystal.perfectDay: PLAYED`, one call | one 890 ms sound |
| t9 | Three completions within 130 ms | one `PLAYED` | one 330 ms sound (plus three clicks); nothing later |
| t10–12 | Select Summit Spark, select Warm Ember, Play Ice Crystal | `PLAYED` each | 440 ms, 390 ms, 330 ms; peaks −10.1 to −10.3 dBFS |
| t13 | Sounds off, completion | no call | touch click only; completion saved |
| t14 | Force-stop, relaunch | launch: no call; first completion `warmEmber.perfectDay: PLAYED` ² | 900 ms; loaded in time on a cold start |
| t15 | Home 20 s, resume | resume: no call; completion `PLAYED` | 390 ms |
| t16 | TalkBack on, double-tap to complete | completion saved, `PLAYED` | **inconclusive**: the stream returned 0.5 s of near-silence in 701 packets, without TalkBack's own speech |
| t17 | R8 release build | starts, no crash; SoundPool player created with sonification attributes | 900 ms Perfect Day sound captured |

¹ Under Do Not Disturb Android reports the ringer as silent
(`dumpsys audio`: priority → internal NORMAL, external SILENT; alarms /
total silence → SILENT / SILENT), so the ringer check answers first.
Either branch keeps the sound off.
² The relaunch re-earned today's Perfect Day in a new process, so its
sound played again ("once per Arc and date **per app process**", § 8.2).

Other checks: tap-to-sound latency 100–230 ms in the captures (adb input,
the save and playback, debug build); the stored row read with `adb root` +
`sqlite3` matched each change (`1|0|warmEmber`, then `1|1|warmEmber`);
Focus Guard's settings read Usage Access and notification state natively
and its app picker listed apps; turning on the daily reminder stored it
and scheduled its alarm; the release APK's sounds are stored
uncompressed. Today's header was confirmed at 360 dp, 1× and 2×, before
and after the fix.

## Unverified device behaviour (unresolved for Gate G)

| Item | Status |
|---|---|
| TalkBack: the sound is heard and doesn't cut the spoken confirmation | **UNRESOLVED.** Completing by double-tap works and the player is asked to play; the capture was inconclusive (t16) |
| Headphones / Bluetooth | **NOT RUN** (no device on the emulator) |
| OnePlus / OxygenOS (AD15's open question) | **NOT RUN**: no physical device was authorised; planned for 12I |
| The stream's own muting without the explicit silence rule | **NOT MEASURED separately**: the rule stops playback first |
| iOS simulator playback and silent switch | **DEFERRED.** `flutter build ios --simulator` succeeds and the app launches to onboarding with the player registered; no sound was triggered or heard |
| Midnight on the device | Covered by a widget test only |
| Loudness on real phone speakers, especially Warm Ember's low register | Owner listening |

## Permission, dependency and network audit

- `pubspec.yaml`: only the `assets/sounds/` declaration; `pubspec.lock`
  unchanged; no Gradle or CocoaPods dependency added (JVM tests use the
  existing JUnit).
- The CI release permission audit, replayed locally on the release APK:
  exactly the expected seven permissions.
- No notification channel, no audio focus request, no `MODIFY_AUDIO_SETTINGS`
  or `ACCESS_NOTIFICATION_POLICY`; no network API in the sound code;
  `network_boundary_test` unchanged and passing.
- Package `com.nextrep.nextrep`, version `1.2.0+3`, schema 7, backup
  format 4 (reads 1–4) unchanged.

## Gate G: listening and decisions for the owner

### How to listen

The six files are in the repository at `assets/sounds/` and in each CI
run's artifact **`nextrep-completion-sounds`** (Actions → the run →
Artifacts). On a Mac:

```
for f in assets/sounds/*_habit.wav; do echo $f; afplay $f; sleep 1; done
for f in assets/sounds/*_perfect_day.wav; do echo $f; afplay $f; sleep 1; done
```

or download the artifact with
`gh run download <run-id> -n nextrep-completion-sounds`. Listening on a
phone speaker at a normal ringer volume is closest to use; a debug build
plays them from Sound & Feedback's Play buttons. To regenerate them from
source: `dart run tool/sounds/generate_completion_sounds.dart`.

### Decisions

1. **The three sets**, by ear: Ice Crystal, Summit Spark, Warm Ember,
   each habit and Perfect Day sound. Restrained enough? Distinct enough?
2. **The names** (spec § 8.3 marks them illustrative).
3. **Default on, Ice Crystal** (AD15, already approved; reconfirm after
   listening).
4. **Loudness balance:** equal peaks (−5 dBFS), but Warm Ember's RMS is
   3–4 dB above the other two; its low register may still sound softer on
   small speakers.
5. **16 kHz files** (size) instead of a higher rate: nothing above 7 kHz.
6. **Explicit silence rule:** any Do Not Disturb mode silences the sound,
   even a priority mode that allows system sounds; an unknown state is
   silent.
7. **Perfect Day memory per process:** a Perfect Day undone and redone
   after an app restart plays the Perfect Day sound again (observed, t14);
   within one process it plays the habit sound.
8. **Never late:** a save slower than 1 s stays silent (a rule added to
   honour "never play late").
9. **A Perfect Day sound inside another sound's 500 ms window is dropped**
   like any other (rapid taps), not given priority.
10. **Today's header** layout change (above).
11. **About**: a new "SETTINGS" row "Sound & Feedback"; the hub link
    "Sound & Feedback"; the stacked preview button's visible text "Play".

### Checklist

- [ ] Independent technical review of the branch
- [ ] Owner listened to all six sounds (not claimed by any test)
- [ ] Names approved or changed
- [ ] Default on / Ice Crystal confirmed
- [ ] Decisions 4–11 answered
- [ ] Unresolved items above accepted for 12G or assigned to 12H / 12I
- [ ] CI green on the final head
- [ ] Owner's merge decision

## Local validation

```
dart format --output=none --set-exit-if-changed .     # 0 changed
flutter analyze                                       # No issues found
flutter test                                          # 2,282 passed
(cd android && ./gradlew :app:testDebugUnitTest)      # 87 passed
flutter build apk --debug && flutter build apk --release
flutter build ios --simulator --debug
dart run tool/sounds/generate_completion_sounds.dart --check
```
