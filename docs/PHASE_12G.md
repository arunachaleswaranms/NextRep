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
| `lib/domain/feedback/sound_origin.dart`, `lib/features/sound/sound_origin_scope.dart` | **New (G-R1).** `SoundOrigin`, the cancellable handle every request carries; `SoundOriginScope`, the mixin that keeps Today's and Sound & Feedback's origin active only while the screen is shown |
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
| Completion restored after a reversal (re-checking, stepping back up, or the clock-time snackbar Undo that restores a goal-met time) | habit, if the 3 s per-habit window allows | W flows 2, 4 |
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
| U | `test/domain/completion_feedback_test.dart` | 33 (10 from G-R1): global 500 ms and still-playing gaps, per-habit 3 s, dropped-not-queued, simultaneous requests, a 200-tap burst, Perfect Day replacement and per-Arc/date memory, throttled Perfect Day, sound off, latency, unreadable setting, failing and hanging player, warm-up, preview, wall-clock rollback and restore through the providers |
| W | `test/features/completion_sound_flow_test.dart` | 9: every § 8.1 row through the real Today screen, commit and ledger, with haptics recorded |
| W | `test/features/completion_sound_stale_test.dart` | 18 (G-R1): stale completions and previews dropped (see the G-R1 section) |
| W / R | `test/features/sound_settings_test.dart` | 22: wording and defaults, choose and preview, off disables with a reason, failed write, relaunch and Restart, format-4 restore and formats 1–3 through Data & Backup, entry points in five app states, six layouts (360×800 at 1× and 2×, 320×568 at 1.5×, landscape at 1.3× and 1×, tablet), `meetsGuideline` tap target / label / contrast at 1× and 2× |
| W | `test/features/completion_sound_regression_test.dart` | 1: the same session with sounds on, off, a failing player, a hung player and every sound cancelled (G-R1) stores identical rows in every table but `feedback_preferences` |
| S | `test/app/completion_sound_boundary_test.dart` | 6: unique channel names; SoundPool, sonification, one stream, no focus or other player; no channel, permission or network; iOS ambient; only Today and the settings screen use the engine; bundled only |
| A | `test/assets/completion_sound_assets_test.dart` | 38 (above) |
| J | `android/app/src/test/.../sound/CompletionSoundsTest.kt` | 16: loading once, bundled paths only, play when loaded, skip before loading and never later, unknown sound, failed load unloaded and retried, missing asset, silent and vibrate, every DND filter, unreadable state, policy table, playback failures, release, late callbacks, fresh engine after release, no channel collision with Focus Guard |

`test/app/network_boundary_test.dart` is unchanged and passes.

Totals on the final local run: **2,311 Flutter tests pass** (127 new,
28 of them from correction G-R1), **87 JVM tests pass** (16 new); `dart format` and `flutter analyze`
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
| t18–19 | Final release build (after the review fixes): normal, then silent | completion saved both times | 890 ms sound; then **0 packets** |

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

## Independent review before the PR

A fresh reviewer read the code cold (no conclusions given). Nothing
critical or high. Outcomes:

| Finding | Outcome |
|---|---|
| M1: the clock-time snackbar Undo after "marked not done" restores the goal-met time and plays the habit sound | **Kept, as specified:** it restores a completion (§ 8.1 "Completion restored after a reversal"); the haptic and "+XP" snackbar fire there too. Now pinned by a test; the owner may read "undo" more strictly (decision 12) |
| L1: the 1 s "never late" drop could silence a sound on a slow device (the save queue also runs the previous action's achievement sync) | Gate G decision 8; emulator latency was 100–230 ms, OnePlus to measure in 12I |
| L2: the Perfect Day memory is per Flutter engine; on Android an Activity finished and relaunched in a warm process starts fresh | Documented with decision 7 |
| L3: iOS marked the session configured even if `setCategory(.ambient)` failed (the default session would stop music) | **Fixed:** nothing loads or plays unless the ambient category was set |
| L4: a failed `SoundPool` load was never unloaded | **Fixed:** unloaded, then retried by the next prepare (JVM test) |
| L5: a preview before loading finishes is silent but takes the 500 ms window | Accepted: the screen warms the sounds up on open |

## Independent review correction G-R1: stale asynchronous playback

Found by the independent review of PR #30 (head `2963e51`). Corrected on
the same branch; the native players, the six sounds and their generator,
and everything stored are unchanged.

### The race

`CompletionFeedback.habitCompleted()` (and `preview()`) read
`feedback_preferences` with an `await` before deciding to play. A
completion could commit, and its sound then wait on that read while:

- the user left Today (a pushed page such as Reminders or Sound &
  Feedback, or another tab);
- the Arc was restarted or ended;
- a restore replaced the app epoch and rebuilt every screen;
- the app went to the background, or Today was disposed.

When the read returned, the old request was still allowed to play. The
same held for a preview whose user had already left Sound & Feedback,
including the preview that follows a set being stored (`_choose` awaits
the save, then previews). Root cause: the engine's only conditions were
the setting, the latency limit and the throttles; nothing tied a request
to the screen, Arc and app state it came from.

### Why `mounted` was not enough

Today lives in a `StatefulShellRoute.indexedStack` branch: it stays
mounted (offstage, tickers off) while Journey, Journal or History is
shown, and every page pushed on the root navigator (Reminders, Sound &
Feedback, About, Restart, …) covers it without disposing it. Sound &
Feedback likewise stays mounted under a page pushed over it. `mounted`
is true in all of these, so `if (!mounted) return` in `_perform` and
`_save` let the stale request through.

### Design

One small pure handle plus one UI mixin; no navigation or Riverpod
dependency in the engine, no new provider, table, column, migration or
dependency.

```
SoundOrigin (lib/domain/feedback/sound_origin.dart)
  isActive; cancel()  ─ permanent, idempotent; never re-activated

SoundOriginScope mixin (lib/features/sound/sound_origin_scope.dart)
  on TodayScreen (soundLocation /today) and SoundSettingsScreen
  (/settings/sound). Holds the origin of the current *visible window*:
    eligible = mounted
             ∧ router's top page is at soundLocation
                 (currentConfiguration.lastOrNull.matchedLocation: a
                  pushed page or the shown tab; .uri stays the base
                  location under a push, so it is not used)
             ∧ TickerMode enabled (indexed-stack tab shown, not under an
                  opaque page)
             ∧ AppLifecycleState.resumed
    not eligible → origin.cancel()
    eligible again → a NEW origin (old requests stay cancelled)
  renewSoundOrigin(): cancel now; new origin if still eligible

Request:  origin = soundOrigin     ─ captured when the user acts,
          … await save …              before any await
          engine.habitCompleted(…, origin) / engine.preview(theme, origin)

CompletionFeedback:
  origin cancelled → SoundOutcome.cancelled (no read)
  await read setting                      ─ the only async boundary
  origin cancelled → SoundOutcome.cancelled
  off / late / Perfect Day choice / per-habit throttle (no state change)
  origin cancelled → SoundOutcome.cancelled   ─ immediately before _start
  _start (global throttle; commits; native play, not awaited)
```

From the check after the read to `_start` the engine does not yield, so
the origin cannot change between the last check and the native call; the
check immediately before `_start` keeps that true if an `await` is ever
added. The native players are asked to play only after all three checks;
there is no delayed native queue.

Origins are per screen, so cancelling a pending preview never cancels a
completion request, and the reverse.

### Invalidation points

| Event | Mechanism | Today | Sound & Feedback |
|---|---|---|---|
| Another tab shown (Today stays mounted) | router top page ≠ `/today`; `TickerMode` off | ✓ | n/a |
| A page pushed over the screen / the screen popped | router top page changes (synchronously, on the delegate's notification) | ✓ | ✓ |
| Arc Restart (new session id) or the Arc ending (status) | `todayControllerProvider` select `(session.id, session.status)` → `renewSoundOrigin` | ✓ | n/a |
| App epoch replaced (restore, re-initialisation) | `appEpochProvider` listener → `renewSoundOrigin`, before the rebuild's frame | ✓ | ✓ |
| App leaves `resumed` (inactive, hidden, paused) | `AppLifecycleListener.onStateChange` | ✓ | ✓ |
| Screen disposed | `dispose()` cancels | ✓ | ✓ |
| Sounds switched off | `renewSoundOrigin` before the save | n/a | ✓ |

Returning to the same route or Arc makes a new origin; the cancelled one
stays cancelled, so nothing is replayed or retried.

### Throttle and Perfect Day state

A cancelled request returns before `_start`, so it takes **no** global
window, writes **no** per-habit time and marks **no** Perfect Day as
sounded: the next eligible completion (even of the same habit, at once)
is judged as if the cancelled one never happened. A sound that had
already started is not stopped. The monotonic clock, the 1 s latency
drop, the 500 ms / 3 s throttles, no-overlap and the per-Arc/date Perfect
Day memory are unchanged.

### Tests added

| File | New | What |
|---|---|---|
| `test/domain/completion_feedback_test.dart` | 10 | Pure engine with every read held on a `Completer` (`HeldFeedbackPreferences`): live origin plays once; cancelled mid-read dropped and never replayed (idempotent cancel); a cancelled origin reads nothing; cancelled in the very microtask the setting returns (last boundary) for completions and previews; no throttle window or Perfect Day memory taken; 8 simultaneous pending requests (one cancelled): exactly one plays, the first live one; sounds off during the read; a failing read after waiting; the 1 s latency rule still applies; a cancelled preview takes nothing from the next |
| `test/features/completion_sound_stale_test.dart` | 18 (new file) | Real app, router and Drift: (1) stays on Today → one sound; (2) Reminders pushed → none, none on return, save stands; (2b) the setting returns after the push but **before the next frame** (Today's tickers still on, so only the location guard applies) → none; (3b) a page pushed outside the router, as Share preview is (location still `/today`, so only the ticker guard applies) → none, the next completion after closing it sounds; (3) Journey tab with Today still mounted (asserted) → none; (4, 9, 10) away and back → none, the next completion sounds at once; (5, 9) Arc Restart with Today still at `/today` → none, the new Arc sounds; (6) Arc ends → none; (7, 9) epoch moved and the setting returned **before any frame** (old Today asserted mounted) → none; (8) backgrounded → none even after resuming; (8) disposed → none; (20) hung and failing player, completions stored. Previews: (11) shown → plays; (12, 13, 15) left and reopened → none, a new preview plays; backgrounded → none; (14) a set chosen, another page pushed over the still-mounted screen before the save finishes → stored, never previewed, not on return either, then left by Back → none; (16) switched off during the read → none (the stored setting); (16b) the same with a read that still says "on" → none (only the switch's cancellation applies) |
| `test/features/completion_sound_regression_test.dart` | runs | The same session now also with a hung player and with every sound held until Today is gone (cancelled; the monotonic clock stands still in that run so every request is dropped by cancellation, not by the latency rule): every table but `feedback_preferences` identical to sounds-on, sounds-off and failing-player |
| `test/app/completion_sound_boundary_test.dart` | assertions | Only the scope creates an active `SoundOrigin`; both sounding screens use the scope |

No test sleeps in real time; every race is ordered by `Completer`s.

**Mutation check (G-R1):** ten mutations, each run against the engine
and stale-request tests, each detected:

| Mutation | Detected by |
|---|---|
| Engine ignores the origin | 6 engine and 13 widget tests |
| Engine checks the origin only before the read | 5 engine and 11 widget tests |
| Scope ignores the router location | 2b |
| Scope ignores `TickerMode` | 3b |
| Scope ignores both (`mounted`-only behaviour) | 2, 3, 4, 14 |
| Scope ignores the app lifecycle | 8 (completion), backgrounded preview |
| No epoch listener | 7 (epoch moved, old Today still mounted) |
| No Arc-identity listener on Today | 5 |
| `dispose` doesn't cancel | 8 (disposed) |
| Turning sounds off doesn't cancel pending previews | 16b |

The location and ticker guards overlap: each alone covers the ordinary
cases, so each has a test of its own (2b, 3b) where the other can't help.

An independent cold review of the correction (code only, no conclusions
given) found no correctness defect. Its lower-confidence notes led to
16b, the still clock in the cancelled regression run, and the residual
limitations below.

### Emulator check

Disposable AVD `NextRep12G_GR1` (API 36 `google_apis` arm64, Pixel 7,
fresh, nothing else installed), the debug build of this correction,
deleted afterwards. Evidence is the debug build's
`NextRepSound: play <id>: <result>` log line (the engine handed the sound
to the native player) beside the app's state; the audio output itself was
not recorded again, since the players and files are unchanged. Two taps in
one `adb shell` command arrive a few tens of milliseconds apart.

| Trial | Measured |
|---|---|
| A. Complete Workout, stay on Today | `play iceCrystal.habit: PLAYED` (the scope is eligible on a device) |
| B. Complete Water Intake and tap the Journey tab in the same command | saved (2 of 4); **no play logged** |
| C. Control: complete Learning and tap a non-navigating spot in the same command | `PLAYED` |
| D1. Preview, then Back in the same command | `PLAYED`: the read finished before Back was handled, so the sound started while the screen was eligible and is not stopped (by design) |
| D2. Control: preview, then a non-navigating tap | `PLAYED` |
| D3. Choose Summit Spark, then Back in the same command | stored (`feedback_preferences` row `summitSpark` read from the device's database); **no preview logged** |
| E. Complete the last habit (a Perfect Day), then Home in the same command | saved (4 of 4, Perfect streak 1); **no play logged**, none after returning to the app |

B, D3 and E show stale requests dropped on a device; C and D2 show the
same timing without leaving still sounds. Whether B and E were dropped by
the cancelled origin rather than another rule is inferred (no throttle or
latency applied: the previous sound was seconds earlier and the action
took well under a second), not logged. Exact race ordering is covered by
the widget tests, not by this check.

### Residual limitations

- The guard covers requests that have not started. A sound already handed
  to the native player plays out (≤ 900 ms); stopping it is out of scope.
- "Eligible" is the screen's own route at the top, tickers on and the app
  resumed. A dialog or bottom sheet over Today (pause / resume sheets, the
  celebration overlay) does not count as leaving; a completion cannot be
  made from under one.
- `inactive` counts as leaving: on Android a visible window that loses
  focus (notification shade, a system dialog, the other side of split
  screen) drops a sound still waiting for its setting. Deliberate (strict
  "foreground"); a pending sound waits only milliseconds.
- A page pushed outside the router (Share preview, a plain
  `Navigator.push`) is detected by the ticker guard only once its forward
  transition completes, so for about 300 ms Today, still partly visible,
  stays eligible. Share starts from a bottom sheet, so a completion sound
  pending in that window is very unlikely. The router's own pages are
  detected at once (their location changes synchronously, and in this app
  they have no transition).
- Race ordering is proved by widget tests with fakes; the emulator check
  above shows the behaviour on a device but cannot order a race exactly.

### Unchanged

Sound assets (SHA-256 below unchanged), their generator, the Android and
iOS players, the channel, `feedback_preferences` persistence, backup and
restore, reminders, Focus Guard, every habit, XP, streak, Perfect Day,
Minimum Day, Restart and Freeze rule. No migration, dependency or
permission.

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
   within one process it plays the habit sound. Strictly the memory lives
   with the Flutter engine, so an Activity finished and reopened in a
   still-warm process also starts fresh.
8. **Never late:** a save slower than 1 s stays silent (a rule added to
   honour "never play late"). Measured 100–230 ms on the emulator; to be
   measured on the OnePlus in 12I, where a slow save would drop the sound.
9. **A Perfect Day sound inside another sound's 500 ms window is dropped**
   like any other (rapid taps), not given priority.
10. **Today's header** layout change (above).
11. **About**: a new "SETTINGS" row "Sound & Feedback"; the hub link
    "Sound & Feedback"; the stacked preview button's visible text "Play".

12. **Undo that restores a completion:** the clock-time snackbar Undo
    after "marked not done" plays the habit sound (as a restored
    completion). Keep, or silence every snackbar Undo?

### Checklist

- [ ] Independent technical review of the branch
- [ ] Owner listened to all six sounds (not claimed by any test)
- [ ] Names approved or changed
- [ ] Default on / Ice Crystal confirmed
- [ ] Decisions 4–12 answered
- [ ] Unresolved items above accepted for 12G or assigned to 12H / 12I
- [ ] CI green on the final head
- [ ] Owner's merge decision

## Local validation

```
dart format --output=none --set-exit-if-changed .     # 0 changed
flutter analyze                                       # No issues found
flutter test                                          # 2,311 passed
(cd android && ./gradlew :app:testDebugUnitTest)      # 87 passed
flutter build apk --debug && flutter build apk --release
flutter build ios --simulator --debug
dart run tool/sounds/generate_completion_sounds.dart --check
```

## Gate G outcome

Recorded in Phase 12H (`docs/PHASE_12H.md`) from the owner's Phase 12H
brief; nothing in this phase's qualification above was re-run or
re-claimed.

- **Gate G (owner): APPROVED on 24 November 2026.**
- All six original completion sounds approved after listening.
- Names approved: **Ice Crystal**, **Summit Spark**, **Warm Ember**.
- Completion sounds **on by default**, **Ice Crystal** selected.
- The remaining Gate G implementation decisions (4–12 above) approved as
  implemented.
- The documented device-qualification deferrals accepted: TalkBack
  audibility and speech continuity, headphones / Bluetooth, OxygenOS,
  iOS playback (carried to Phase 12H / 12I).
- Review correction G-R1 resolved; its residual limitations stand as
  documented above.
- Merged as PR #30: final head `a1147a4032fd409e7b88ca812c38ea33430103f3`,
  squash merge `20712d21c1ec02bf3eba18222f3eeeafe7182a0d`; post-merge CI
  run 45388828817 passed both jobs. No release was created from Phase
  12G.
