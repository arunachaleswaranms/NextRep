# Release checklist

Run this top to bottom for every store release. Tick an item only after
doing it for **this** build. Items ticked below were done in Phase 7 on
2026-10-05, at the commit named in [PROJECT_STATE.md](../PROJECT_STATE.md).
Unticked items are still open, and some can only be done by the owner (an
account, a key, a physical device).

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
- [x] Generated code unchanged: `dart run build_runner build --delete-conflicting-outputs` leaves no diff (only needed after a table change)
- [ ] CI green on the release commit (Flutter CI: quality, Android builds and permission audit)

## Android

- [x] `flutter build apk --debug`
- [x] `flutter build apk --release` (debug-signed: compile and QA only)
- [x] `flutter build appbundle --release` (debug-signed: **not uploadable**)
- [x] Release permission audit: `aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk`
  - `INTERNET`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `MANAGE/READ/WRITE_EXTERNAL_STORAGE` absent
- [ ] **Signing**: upload key in `android/key.properties`; `keytool -printcert -jarfile app-release.aab` shows the upload key, not `CN=Android Debug` ([ANDROID_SIGNING.md](ANDROID_SIGNING.md))
- [x] Emulator (API 36), release build: launch, notification permission (deny, then allow), reminders scheduled, document picker
- [ ] Physical Android device, release build of this commit: install over the previous version, cold launch, background / resume, force stop / relaunch
- [ ] Physical: notification permission, a delivered reminder, a tap from the background and from a cold start, revoked permission
- [ ] Physical: backup export through the document picker, restore, a corrupted file refused
- [ ] Physical: keyboard, landscape, large text, reduced motion ("Remove animations"), Journey and Today scrolling

## iOS

- [x] `flutter build ios --simulator`
- [x] `flutter build ios --release --no-codesign`
- [x] Simulator integration tests (`flutter test integration_test -d <simulator> --no-uninstall`)
- [ ] Physical iPhone: install, notification permission, a delivered reminder, a notification tap
- [ ] Physical iPhone: backup export and import through Files, the bedtime picker, background / resume, performance
- [ ] **Signing**: Apple Developer team, distribution certificate, App Store provisioning profile for the final bundle id

## Product

Each of these is covered by automated tests (widget and integration). A
manual pass on a physical device is still required before release.

- [x] Onboarding (fresh install → Today)
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

- [x] Semantics: labels, states and tap actions (`phase7_accessibility_test.dart`)
- [x] Text scale 1.3× and 2× on the priority screens (widget tests)
- [x] Reduced motion (widget tests, and the scene stops)
- [x] Touch targets (`androidTapTargetGuideline` on Today)
- [ ] TalkBack pass on a physical Android device
- [ ] VoiceOver pass on an iPhone

## Store

- [ ] **Identifiers**: final Android `applicationId` and iOS bundle id chosen (currently `com.nextrep.nextrep`, see [STORE_READINESS.md](STORE_READINESS.md))
- [ ] **Version**: release `version:` in `pubspec.yaml` chosen and the build number incremented
- [x] Icon (launcher, adaptive and themed, iOS set, store icons)
- [ ] Screenshots ([STORE_METADATA.md](STORE_METADATA.md#screenshots))
- [ ] Play feature graphic
- [x] Metadata drafted ([STORE_METADATA.md](STORE_METADATA.md))
- [x] Privacy description ([PRIVACY.md](../PRIVACY.md))
- [ ] Privacy policy published at a public URL, with a contact address
- [ ] Android system-backup decision recorded (keep, or `allowBackup="false"`)
- [ ] Play Data safety and App Store privacy details filled in
- [ ] **Production signing** (Android upload key; iOS distribution)
