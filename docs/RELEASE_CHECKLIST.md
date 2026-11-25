# Release checklist

> **Distribution model (Phase 9):** NextRep ships as a signed APK on GitHub
> Releases ([DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md)). For a
> release, run a fresh **Direct distribution** record below (copy the
> latest one; never tick an item from an earlier release) plus the Code
> section. The iOS, TalkBack, VoiceOver and Store items below are Phase 7–8
> history. Store publication is not planned, so they don't block a release.
>
> **From v1.2.0 (Phase 11D):** the release permission set includes
> `INTERNET`, for the manual update check only; the release script and CI
> require exactly that set. Publish the GitHub Release as a full release
> with both assets attached, or the in-app check reports it as not ready
> ([DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md#checking-for-updates-from-the-app)).

## Direct distribution: v1.3.0 (Phase 12I)

A fresh record for v1.3.0, started in Phase 12I on 2026-11-25. Nothing is
carried over from v1.2.0 or from an earlier v1.3 phase. Tick an item only
with evidence in [PHASE_12I.md](PHASE_12I.md) for **this** release's
source.

Source and identity

- [x] `pubspec.yaml` `1.3.0+4`; `appVersion` `1.3.0`; planned tag `v1.3.0` (not created)
- [x] `applicationId` `com.nextrep.nextrep`, minSdk 24, targetSdk 36; no temporary suffix in the source
- [x] Schema **v7**, backup write **4** / read 1, 2, 3, 4; 32 achievements; no new permission or dependency; `AndroidManifest.xml` and `pubspec.lock` unchanged from `main`
- [x] `android/key.properties` in the signing checkout points at the permanent key (git-ignored, mode 600, values never read or printed); the key was not rotated

Automated (candidate source `9ce26ee`)

- [x] `dart format --output=none --set-exit-if-changed .` (421 files, 0 changed), `flutter analyze` (no issues)
- [x] `flutter test` 2,460 / 2,460 and `./gradlew :app:testDebugUnitTest` 87 / 87
- [x] Focused suites: migrations v1 → v7, backups 1–4, Weekly Review, Calendar, 12D, 12E2, 12F, 12G (incl. G-R1), 12H, Focus Guard, update check and network boundary, release qualification incl. `phase12i_release_test`
- [x] Completion sounds reproduce from source (6 files, 125,064 bytes)
- [x] `flutter build apk --debug`, `flutter build apk --release` in a worktree without the key (debug-signed, never distributed)
- [x] `flutter build ios --simulator`, `flutter build ios --release --no-codesign` (1.3.0 / 4), iOS About and v1.2 smokes on the simulator
- [ ] Historical iOS integration smokes of phases 3–6: stale, fail identically on the baseline `138fc6f` (deferred; not a blocker)

Signed candidate

- [x] Owner permission to detach the signing checkout; `flutter clean`, then `tool/release/prepare_android_release.sh` on `9ce26ee`; checkout restored to its branch afterwards
- [x] One signer `65:B7:0C:D0:…:F0:BA` (not `CN=Android Debug`), v2 scheme, `com.nextrep.nextrep` 1.3.0 (4), staged APK and `.sha256`
- [x] Independent audit against the published v1.2.0 APK: permissions identical (7), components identical (19), Focus Guard provider not exported, R8 constructors kept, six sounds stored uncompressed, not debuggable
- [x] Byte-identical across two clean builds of `9ce26ee`: 68,142,073 bytes, `a706759703f8894c2ef33772bb7d48a04e23fb0685b0e0639ffce8997754ec7f`
- [x] Size and SHA-256 in [releases/v1.3.0.md](releases/v1.3.0.md)
- [ ] Rebuilt on the PR's final head (docs-only after `9ce26ee`) and on merged `main`: byte-identical (Gate P step)

Emulator (disposable AVDs, synthetic data)

- [x] Published v1.2.0 (checksum, signer, 1.2.0 (3)) with data made by v1.2.0's own services and UI → genuine format-3 export → `adb install -r` of the signed candidate: Success, same signer, `firstInstallTime` unchanged
- [x] Real v6 → v7: every v6 row of 11 tables identical (1,187), only `closed_on` added (null), new tables empty, integrity and foreign keys clean
- [x] Sounds default on / Ice Crystal; reminders, Hydration Coach and Focus Guard kept (not a restore)
- [x] Focus Guard: a natural JobScheduler run after the upgrade, `:focus_guard` reads schema 7, one nudge; reboot and force-stop recovery
- [x] Format-3 restore after the upgrade: Arc data identical, reminders / Hydration / Focus Guard off, no XP, achievement or sound; device sound setting kept; new exports format 4
- [x] v1.2.0 refuses a genuine format-4 file and changes nothing (database byte-identical)
- [x] Minified smoke of the signed candidate: fresh install, setup ordering, saved setup, Confirm & Start, Today, Minimum and Perfect Day, Weekly Review, Calendar, Journey, Journal, Insights, Pause / Cancel / paused / Resume, Restart, ended history, typed DELETE, Sound & Feedback, reminders, Hydration, Focus Guard, Data & Backup, background, process death
- [x] D-1 (6.68 : 1 dark text on Replace Data and Cancel Setup), D-2 (restart on the resume day keeps the pause), C-1 ("Cancel Setup"), C-2 ("8 habits (7 on)")
- [x] Sounds: one playback per completion, Perfect Day once, preview, none when off, on silent, on Do Not Disturb or on restore; no audio focus
- [x] Per-UID network: zero bytes until **Check for updates** is tapped; one request; "newer than the latest published v1.2.0"

Physical Android (OnePlus): **Gate I, pending the owner's explicit authorization**

- [ ] Device identity, installed official v1.2.0 (3) byte-identical to the published asset, its signer, first-install time
- [ ] Pre-upgrade backup exported in v1.2.0 (format 3), verified, kept on the phone and off-device
- [ ] `adb install -r` of the signed candidate (no `-d`, no uninstall, no data clear): Success, same signer, `firstInstallTime` unchanged
- [ ] Real v6 → v7 migration: the same user data as the pre-upgrade backup
- [ ] Physical smoke of every v1.3 feature
- [ ] Sounds on ringer, silent, vibrate, Do Not Disturb, with music, with headphones / Bluetooth; the 1 s rule (U-4)
- [ ] TalkBack swipe order, double-tap, speech continuity during a sound, confirmed by a person listening (U-1, U-2)
- [ ] Optional phone timings (U-8)

Documents and review

- [x] Release notes [releases/v1.3.0.md](releases/v1.3.0.md) (status: release candidate, not published)
- [x] README, CHANGELOG, PRIVACY, DIRECT_DISTRIBUTION, PROJECT_STATE updated; [PHASE_12I.md](PHASE_12I.md)
- [x] Secret audit: no keystore, `key.properties`, password, token, APK, `.sha256`, personal backup, database or device dump tracked ([PHASE_12I.md § S](PHASE_12I.md#s-secret-artifact-and-data-audit))
- [ ] CI green on the final PR head (see the PR)
- [ ] Owner: independent review, Gate I decision, then merge

Publication: separate owner authorization (Gate P), **not started**

- [ ] On merged `main`: `flutter clean` + release script; SHA-256 byte-identical to `a7067597…54ec7f`
- [ ] Tag `v1.3.0` (annotated) on the merge commit; draft with exactly `NextRep-v1.3.0-android.apk` and `.sha256`, downloaded and compared, then published as a full release
- [ ] `releases/latest` API (unauthenticated): `tag_name` v1.3.0, both assets; public download byte-identical, SHA-256 and signer match
- [ ] On an upgraded phone: About → Check for updates → "Latest published: v1.3.0"

## Direct distribution: v1.2.0 (Phase 11F)

A fresh record for v1.2.0, started in Phase 11F on 2026-10-16. Nothing is
carried over from v1.1.0. Tick an item only with evidence in
[PHASE_11F.md](PHASE_11F.md) for **this** release's source.

Source and identity

- [x] `pubspec.yaml` `1.2.0+3`; `appVersion` `1.2.0`; planned tag `v1.2.0` (not created during qualification; created at publication, below)
- [x] `applicationId` `com.nextrep.nextrep`, minSdk 24; no temporary suffix in the source
- [x] Schema **v6**, backup write **3** / read 1, 2, 3; 32 achievements; no new feature, permission or dependency
- [x] `android/key.properties` points at the permanent key (git-ignored, never printed); the key was not rotated

Automated

- [x] `dart format --output=none --set-exit-if-changed .` (305 files, 0 changed), `flutter analyze` (no issues)
- [x] `flutter test` 1265 / 1265 and `./gradlew :app:testDebugUnitTest` 67 / 67
- [x] Focused suites: migrations v1 → v6, backups 1 / 2 / 3, Focus Guard, update check, release qualification, Phase 11E, Phase 11F release tests
- [x] `flutter build apk --debug`, `flutter build apk --release` in a worktree without the key (debug-signed, never distributed)
- [x] `flutter build ios --simulator`, `flutter build ios --release --no-codesign`, iOS simulator smokes

Signed candidate

- [x] `flutter clean`, then `tool/release/prepare_android_release.sh` on the candidate commit: one signer `65:B7:0C:D0:…:F0:BA` (not `CN=Android Debug`), `com.nextrep.nextrep` 1.2.0 (3), exactly the 7 approved permissions, components, R8 constructors, staged APK and `.sha256`
- [x] Independent `apksigner` / `aapt2` / `apkanalyzer` audit of the staged APK
- [x] Byte-identical across two clean builds of `bc4009f` (`e3847628…de3e2`), and again on the PR head `c59a051` (docs only after it)
- [x] Size and SHA-256 written into [releases/v1.2.0.md](releases/v1.2.0.md)

Emulator (disposable AVD)

- [x] Published v1.1.0 (signed) with real data → `adb install -r` of the signed candidate: Success, `firstInstallTime` unchanged, schema v5 → v6, every v5 row unchanged, opt-ins off, reminders kept
- [x] Minified smoke of the signed candidate: About 1.2.0 (3), Today, habits, XP, Journal, Hydration Coach, Focus Guard (Usage Access, a real background check), notification taps, backup export and restore, relaunch
- [x] Per-UID network: zero bytes until **Check for updates** is tapped; one request; "newer than the latest published v1.1.0"

Physical Android (OnePlus CPH2707, Android 16): run 17–18 October 2026 with the owner's explicit authorization

- [x] Device identity, installed official v1.1.0 (2) byte-identical to the published asset, its signer `65b70cd0…f0ba`, first-install time 2026-10-08 22:02:50
- [x] Pre-upgrade backup exported in v1.1.0 (format 2), checksum and validator OK, kept on the phone and off-device (read-only)
- [x] `adb install -r` of the signed candidate (no `-d`, no uninstall, no data clear): Success, same signer, `firstInstallTime` unchanged
- [x] Real v5 → v6 migration: same user data as the pre-upgrade backup; Hydration Coach and Focus Guard off; reminders as before
- [x] Physical smoke: Today, Journey, Journal, Insights, History, Achievements, Reminders, Data & Backup, About, background / resume, force-stop / relaunch, reboot (OxygenOS delivered `BOOT_COMPLETED` ~10 min late; recovery followed it)
- [x] Physical Hydration Coach, Focus Guard and notification checks (real deliveries of all four kinds, tap routing, natural Focus Guard runs, permission revoke / regrant); settings restored afterwards
- [x] Physical manual update check: zero bytes until the tap, one request (9,437 / 1,490 bytes), "newer than the latest published v1.1.0"
- [x] Post-upgrade backup: format 3, checksum OK, equivalent data; original backup kept

Documents and review

- [x] Release notes [releases/v1.2.0.md](releases/v1.2.0.md) with the verified size, SHA-256 and physical result
- [x] README, CHANGELOG, PRIVACY, DIRECT_DISTRIBUTION, PROJECT_STATE updated; [PHASE_11F.md](PHASE_11F.md)
- [x] Secret audit: no keystore, `key.properties`, password, token, APK, `.sha256`, personal backup or device dump tracked
- [x] CI green on the final PR head (run 39093437696 on `308a0d6`, both jobs)
- [x] Owner: independent review, then merge (PR #20 → `8ab0c43`; main CI run 39096524587 green, both jobs)

Publication: separate owner authorization (Gate D), done 2026-10-18. Evidence: [PHASE_11F.md](PHASE_11F.md#aj-publication-outcome-gate-d)

- [x] On merged `main` (`8ab0c43`): `flutter clean` + release script (1265 / 1265); SHA-256 `e3847628…de3e2`, byte-identical to the qualified candidate
- [x] Tag `v1.2.0` (annotated) on `8ab0c43`; draft with exactly `NextRep-v1.2.0-android.apk` and `NextRep-v1.2.0-android.apk.sha256`, downloaded and compared, then published as a full (not draft, not pre-) GitHub Release "NextRep v1.2.0"
- [x] `releases/latest` API (unauthenticated): `tag_name` v1.2.0, `draft` false, `prerelease` false, both assets uploaded; publicly downloaded APK byte-identical, SHA-256 and signer match
- [ ] On the upgraded phone: About → Check for updates → "You're using the latest published version. Latest published: v1.2.0" (authorized; **NOT RUN**, the phone wasn't reachable over wireless adb)

## Direct distribution: v1.1.0 (Phase 10D)

Done for v1.1.0 in Phase 10D on 2026-10-12, on the PR head. Evidence:
[PHASE_10D.md](PHASE_10D.md).

- [x] `pubspec.yaml` version is the release (`1.1.0+2`; `app_info.dart` matches); the planned tag is `v1.1.0` (not created)
- [x] `applicationId` is still `com.nextrep.nextrep`
- [x] Schema and backup format unchanged (v5, export format 2, import 1 and 2)
- [x] `android/key.properties` points at the permanent release key and is git-ignored; the key was not rotated
- [x] Gates: format clean, analyze clean, `flutter test` 769 / 769, coverage 93.8%, migrations 39, backup 76, release qualification 39, Phase 10A 78 / 10B 63 / 10C 102
- [x] `flutter clean`, then `tool/release/prepare_android_release.sh`: one signer `65:B7:0C:D0:…:F0:BA` (not `CN=Android Debug`), `com.nextrep.nextrep` 1.1.0 (2), minSdk 24, targetSdk 36, permission audit (no network, exact-alarm, storage, media, contacts, accounts, camera, microphone or usage access), staged APK and `.sha256`
- [x] Byte-identical across two clean builds of the same commit in the fixed local environment (`f6bf2a3a…a2d779`), and again on the final head
- [x] `flutter build apk --debug`, `flutter build ios --simulator`, `flutter build ios --release --no-codesign`
- [x] Physical Android (OnePlus CPH2707, Android 16): the installed official v1.0.0 verified byte-identical to the published asset, backup exported first, `adb install -r` of v1.1.0 → Success, `firstInstallTime` unchanged, same signer, data intact with no restore
- [x] Physical smoke: cold launch, Today, Journey, Journal, Insights, History, Achievements (6 categories, 32), reminders, Data & Backup, force-stop / relaunch, background / resume
- [x] Physical share: Today's Progress (privacy switches), My Arc, Achievement; native chooser, cancel, no duplicate chooser, WhatsApp picker reached and backed out (nothing sent)
- [x] Share output carries no repository link: card footer "Made with NextRep" only, caption without a URL; corrected candidate installed over the earlier v1.1.0 build (`adb install -r` Success, data intact) and the three cards and caption re-checked on the phone
- [x] Physical backup after the update: format 2, checksum valid, data identical to the pre-update backup
- [x] Emulator: v1.0.0 → v1.1.0 backfill (one combined celebration for the active Arc, completed Arc silent, historical dates, XP unchanged), Minimum Day return to full targets, Sleep Before copy, the six templates in setup and the 12-habit limit
- [x] Release notes in `docs/releases/v1.1.0.md`, with the APK size and SHA-256
- [x] README, CHANGELOG, PRIVACY, DIRECT_DISTRIBUTION, PROJECT_STATE updated
- [x] Secret audit: no keystore, `key.properties`, password, token, APK, personal backup or device dump tracked
- [x] CI green on the final PR head (see PR for the current run)
- [ ] TalkBack human pass (deferred; not a blocker)
- [ ] Owner: after review and merge, rebuild on `main`, confirm the SHA-256, tag `v1.1.0` and publish the GitHub Release with the APK, its `.sha256` file and the release notes

## Direct distribution: v1.0.0 (Phase 9)

Done for v1.0.0 in Phase 9 on 2026-10-08. Evidence:
[PHASE_9.md](PHASE_9.md).

- [x] `pubspec.yaml` version is the release (`1.0.0+1`); the planned tag is `v<versionName>`
- [x] `applicationId` is still `com.nextrep.nextrep`
- [x] Schema and backup format unchanged, or migrated and tested (v5, format 2)
- [x] `android/key.properties` points at the permanent release key and is git-ignored ([ANDROID_SIGNING.md](ANDROID_SIGNING.md))
- [x] `flutter clean`, then `tool/release/prepare_android_release.sh`: gates, build, signer (not `CN=Android Debug`, certificate `65:B7:0C:D0:…:F0:BA`), package and version, permission audit, staged APK and `.sha256`
- [x] Physical Android: `adb install -r` of a same-key build over the previous install keeps the data (signed update continuity)
- [x] Physical Android smoke: cold launch, Today, Journey, Journal, Insights, History, backup screen, reminders, force-stop / relaunch
- [x] Release notes in `docs/releases/v<version>.md`, with the APK SHA-256
- [x] README, CHANGELOG and PROJECT_STATE updated
- [x] CI green on the release commit (run 37811403687 on `b1aeb05`)
- [ ] Owner: after merge, tag `v<version>` and publish the GitHub Release with the APK, its `.sha256` file and the release notes
- [ ] Owner: keystore backed up in two secure places, password in a password manager

## Store-release record (Phases 7–8)

Run this top to bottom for every store release. Tick an item only after
doing it for **this** build. Items ticked below were done in Phase 8 on
2026-10-06, on the commit named in [PROJECT_STATE.md](../PROJECT_STATE.md).
Evidence for each is in [PHASE_8.md](PHASE_8.md). Physical Android items
were done in Phase 8.5 on 2026-10-07/08, on a OnePlus CPH2707 (Android 16).
Evidence for those is in
[PHASE_8_5_PHYSICAL_ANDROID.md](PHASE_8_5_PHYSICAL_ANDROID.md).

Unticked items are still open, and some can only be done by the owner (an
account, a key, a physical device). Emulator and simulator runs never tick
a physical item.

Environment: Flutter 3.47.5 / Dart 3.13.4. Android builds use JDK 21
(`JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`).

## Code

- [x] `dart format --output=none --set-exit-if-changed .`
- [x] `flutter analyze` (no issues)
- [x] `flutter test` (all green)
- [x] Migration suite, v1 → v5:
  `flutter test test/data/migration_test.dart test/data/migration_v3_test.dart test/data/migration_v4_test.dart test/data/migration_v5_test.dart`
- [x] Backup suite, format 1 and 2:
  `flutter test test/domain/backup_format_test.dart test/domain/backup_v2_test.dart test/data/backup_restore_test.dart test/data/backup_v2_restore_test.dart`
- [x] Release qualification:
  `flutter test test/app/day_change_test.dart test/domain/date_edges_test.dart test/features/phase7_lifecycle_test.dart test/features/phase7_accessibility_test.dart`
- [x] `flutter test --coverage`
- [x] No table change in Phase 8, so no `build_runner` run was needed
- [ ] CI green on the release commit (Flutter CI: quality, Android builds and permission audit). Record the run in PROJECT_STATE.md.
- [x] Secret audit: no keystore, `key.properties`, password, private key, provisioning profile, API key or token tracked

## Android

- [x] `flutter build apk --debug`
- [x] `flutter build apk --release` (debug-signed: compile and QA only)
- [x] `flutter build appbundle --release` (debug-signed: **not uploadable**)
- [x] Release permission audit: `aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk`
  - `INTERNET`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` and `MANAGE/READ/WRITE_EXTERNAL_STORAGE` are absent
- [ ] **Signing**: the upload key is in `android/key.properties`, and `keytool -printcert -jarfile app-release.aab` shows the upload key, not `CN=Android Debug` ([ANDROID_SIGNING.md](ANDROID_SIGNING.md))
- [x] Emulator (API 36), release build:
  - in-place upgrade from schema v5 data, and from a Phase 5 (schema v4) release
  - fresh install
  - core flow, notifications, document-picker backup, 2× text, "Remove animations"
- [x] Physical Android device, release build of this commit: install over the previous version, cold launch, background / resume, force stop / relaunch (Phase 8.5; same version and schema, so no migration ran on the device)
- [x] Physical: notification permission, a delivered reminder, a tap from the background and from a cold start, revoked permission, reboot recovery (Phase 8.5)
- [x] Physical: backup export through the document picker (Files), restore, a corrupted copy refused (Phase 8.5)
- [ ] Physical: backup export to Drive through the document picker
- [x] Physical: keyboard, landscape, large text, reduced motion (animator scales 0), Journey and Today scrolling, themed icon (Phase 8.5)
- [x] Physical: `flutter run --profile` frame check of Today and the Journey (Phase 8.5: no frame over 16.7 ms, none over the 90 Hz budget while scrolling)

## iOS

- [x] `flutter build ios --simulator`
- [x] `flutter build ios --release --no-codesign`
- [x] Simulator integration tests (`flutter test integration_test -d <simulator> --no-uninstall`)
- [ ] Physical iPhone: install (blocked until signing exists), notification permission, a delivered reminder, a notification tap
- [ ] Physical iPhone: backup export and import through Files, the bedtime picker, background / resume, performance
- [ ] **Signing**: Apple Developer team, distribution certificate, App Store provisioning profile for the final bundle id

## Product

Each of these is covered by automated tests (widget and integration) and
was also run by hand on the emulator's release build in Phase 8. A manual
pass on a physical device is still required.

- [x] Onboarding (fresh install → Today), and restore from onboarding
- [x] Rolling Arc (start, Day 92 → 93 close-out, summary, new arc)
- [x] Seasonal Arc (preseason setup, Oct 1 join, Dec 31 → Jan 1 close-out, expired setup)
- [x] Late join (neutral pre-join days, season day numbers)
- [x] Custom habits (setup, 12-habit limit, duplicates)
- [x] timeBefore / Sleep Before Target
- [x] Minimum Day
- [x] Perfect Day
- [x] Backup export
- [x] Restore (preview, confirmation, rollback, reminders off, format 1 and 2)
- [x] Journal
- [x] Insights
- [ ] Manual product pass on a physical device

## Accessibility

- [x] Semantics: labels, states and tap actions (`phase7_accessibility_test.dart`; the node tree checked on the emulator)
- [x] Text scale 1.3× and 2× on the priority screens (widget tests; 2× on the emulator)
- [x] Reduced motion (widget tests; "Remove animations" on the emulator)
- [x] Touch targets (`androidTapTargetGuideline` on Today)
- [ ] TalkBack pass on a physical Android device (adb input can't drive TalkBack's gestures). Phase 8.5: onboarding, Arc choice and habit setup were done by the owner; the node tree of every other screen was checked on the phone; the rest of the human pass is open
- [ ] VoiceOver pass on an iPhone

## Store (not planned; Phase 7–8 history)

- [ ] **Identifiers**: final Android `applicationId` and iOS bundle id chosen (currently `com.nextrep.nextrep`; see [STORE_READINESS.md](STORE_READINESS.md))
- [ ] **Version**: release `version:` in `pubspec.yaml` chosen and the build number set (currently `1.0.0+1`, the scaffold value)
- [x] Icon (launcher, adaptive and themed, iOS set, store icons)
- [ ] Screenshots: Play phone drafts captured (1080 × 2160, synthetic, not uploaded); iPhone 6.9" and iPad 13" not captured ([STORE_METADATA.md](STORE_METADATA.md#screenshots))
- [ ] Play feature graphic (concept only)
- [x] Metadata drafted ([STORE_METADATA.md](STORE_METADATA.md))
- [x] Privacy description ([PRIVACY.md](../PRIVACY.md)), still accurate in Phase 8
- [ ] Privacy policy published at a public URL, with a contact address and the publisher's name
- [ ] Android system-backup decision recorded (keep, or `allowBackup="false"`)
- [ ] Play Data safety and App Store privacy details filled in
- [ ] **Production signing** (Android upload key; iOS distribution)
