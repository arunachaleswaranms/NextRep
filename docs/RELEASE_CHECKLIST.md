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

## Direct distribution: v1.2.0 (Phase 11F)

A fresh record for v1.2.0, started in Phase 11F on 2026-10-16. Nothing is
carried over from v1.1.0. Tick an item only with evidence in
[PHASE_11F.md](PHASE_11F.md) for **this** release's source.

Source and identity

- [x] `pubspec.yaml` `1.2.0+3`; `appVersion` `1.2.0`; planned tag `v1.2.0` (not created)
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

Physical Android (OnePlus CPH2707, Android 16): needs the owner's explicit authorization

- [ ] Device identity, installed official v1.1.0 (2), its signer, first-install time
- [ ] Pre-upgrade backup exported in v1.1.0 (format 2), checksum and validator OK, kept off-device
- [ ] `adb install -r` of the signed candidate (no `-d`, no uninstall, no data clear): Success, same signer, `firstInstallTime` unchanged
- [ ] Real v5 → v6 migration: same user data as the pre-upgrade backup; Hydration Coach and Focus Guard off; reminders as before
- [ ] Physical smoke: Today, Journey, Journal, Insights, History, Achievements, Reminders, Data & Backup, About, background / resume, force-stop / relaunch, reboot
- [ ] Physical Hydration Coach, Focus Guard and notification checks (as authorized)
- [ ] Physical manual update check: zero bytes until the tap, one request, "newer than the latest published v1.1.0"
- [ ] Post-upgrade backup: format 3, checksum OK, equivalent data; original backup kept

Documents and review

- [ ] Release notes [releases/v1.2.0.md](releases/v1.2.0.md) with the verified size, SHA-256 and physical result
- [x] README, CHANGELOG, PRIVACY, DIRECT_DISTRIBUTION, PROJECT_STATE updated; [PHASE_11F.md](PHASE_11F.md)
- [x] Secret audit: no keystore, `key.properties`, password, token, APK, `.sha256`, personal backup or device dump tracked
- [ ] CI green on the final PR head
- [ ] Owner: independent review, then merge

Publication: separate owner authorization (Gate D)

- [ ] On merged `main`: `flutter clean` + release script; SHA-256 equal to the qualified candidate
- [ ] Tag `v1.2.0` on the release commit; full (not draft, not pre-) GitHub Release "NextRep v1.2.0" with exactly `NextRep-v1.2.0-android.apk` and `NextRep-v1.2.0-android.apk.sha256`
- [ ] `releases/latest` API: `tag_name` v1.2.0, `draft` false, `prerelease` false, both assets uploaded; downloaded asset SHA-256 and signer match
- [ ] On the upgraded phone: About → Check for updates → "You're using the latest published version. Latest published: v1.2.0"

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
