# PROJECT_STATE

_Last updated: 2026-10-08. Phase 8 merged (PR #8). Phase 8.5 (physical
Android qualification) complete on its branch; PR open, not merged._

**SOFTWARE RELEASE CANDIDATE: PASS · PHYSICAL ANDROID: PARTIAL (TalkBack
human pass outstanding) · STORE SUBMISSION: MANUAL GATES REMAIN**

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `a454230` (squash merge of PR #8, Phase 8). PRs #1–#8
  are Phases 1–8.
- Branch: `phase/8-5-physical-android-qualification`, from `a454230`
- Phase 8.5 changes: one screen-reader label fix (the bedtime card said
  "not logged" twice) with a regression test, and the qualification docs
- PR: #9 (https://github.com/arunachaleswaranms/NextRep/pull/9), open for
  review, not merged
- Phase 8.5 CI: Flutter CI run 37685338871 on `3d2f087`: **green** (Format,
  analyze and test; Android builds and permission audit). Later commits
  are docs only.
- Phase 8 CI: Flutter CI run 37510250285 on `fbf026e`: **green**
- Author and committer of every commit:
  `Arunachaleswaran M S <arunachaleswaranms@gmail.com>` (repo-local
  config). No AI or co-author trailers.

## Environment

- Flutter 3.47.5 stable / Dart 3.13.4 at `~/development/flutter` (not on
  PATH)
- Android builds: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- Emulator: AVD `RideLink_API36` → `emulator-5554`
- iOS: Xcode 27 beta, Swift Package Manager, iPhone 17 simulator (iOS 27)
- Integration tests: always pass `--no-uninstall`
- Dev tools (not tests):
  - `flutter test tool/brand_assets/generate_brand_assets.dart`
  - `SCREENSHOT_DATE=<date> flutter test tool/screenshots/generate_screenshot_backup.dart`

## Versions

- Database schema: **v5** (unchanged)
- Backup `formatVersion`: **2** (reads 1 and 2; unchanged)
- App version: `1.0.0+1`. **FIRST PUBLIC VERSION — OWNER DECISION
  REQUIRED.**

## Results (final code)

| Gate | Result |
|---|---|
| format / analyze | clean / no issues |
| `flutter test` | **605 / 605** (604 at the Phase 8.5 baseline) |
| Coverage | **93.3%** handwritten lib (91.8% including `schema_versions.dart`) |
| Migrations / backup 1+2 / release qualification | 39 / 70 / 38 |
| Integration: emulator-5554 / iPhone 17 simulator | **7 / 7** / **7 / 7** |
| APK debug / release, AAB | PASS (release and AAB debug-signed, `CN=Android Debug`, **not uploadable**) |
| iOS simulator / release no-codesign | PASS / PASS |

## Devices

- **Physical Android (Phase 8.5): PARTIAL.** OnePlus CPH2707, Android 16
  (API 36), wireless adb, release build with QA signing. Evidence:
  [docs/PHASE_8_5_PHYSICAL_ANDROID.md](docs/PHASE_8_5_PHYSICAL_ANDROID.md).
  Phase 8 itself recorded physical Android as manual, because no device
  was connected then. Everything passed except the human TalkBack pass:
  - in-place install over real data, lifecycle and the core flow
  - real reminder delivery, background and cold-start taps, denial,
    revocation, and reboot recovery
  - document-picker export and restore, corrupt copy refused
  - 2× text, reduced motion, landscape, icon and splash
  - profile frames within the 90 Hz budget
- **Emulator (API 36), release build (Phase 8): PASS.** Covered:
  - in-place upgrades from v5 data and from a Phase 5 (v4) release
  - fresh install and the core flow
  - notifications (deny, allow, delivery, background and cold-start taps,
    revocation)
  - DocumentsUI export and restore, corrupt copies refused
  - 2× text, "Remove animations", icons and splash
- **TalkBack: MANUAL REQUIRED.** adb input bypasses TalkBack's gestures.
  On the phone the owner went through onboarding, Arc choice and habit
  setup with TalkBack, but not the rest. The node tree was checked on the
  phone for every other screen: no unlabelled actions, and "1 reflection"
  and "N of 15 achievements" are correct.
- **Physical iOS: MANUAL REQUIRED** (none connected), and install is
  blocked by signing. **VoiceOver: MANUAL REQUIRED.**
- Found and fixed (all P2): in Phase 8, the level row cut short at 2×,
  "1 reflections" and a doubled spoken period; in Phase 8.5, the bedtime
  card saying "not logged" twice. No P0 or P1.

## Release configuration

- **Identifiers:** `com.nextrep.nextrep` on both platforms. **FINAL
  IDENTIFIER DECISION — REQUIRED BEFORE STORE REGISTRATION.**
- **Android system backup:** enabled (`allowBackup` unset). **OWNER
  DECISION REQUIRED.**
- **Android signing:** no `key.properties`. **ANDROID STORE SIGNING —
  MANUAL REQUIRED.**
- **iOS signing:** no team. **IOS STORE SIGNING — MANUAL REQUIRED.**
- **QA artifact hashes:** `docs/PHASE_8.md#android-signing-and-artifacts`;
  the Phase 8.5 release APK in
  `docs/PHASE_8_5_PHYSICAL_ANDROID.md#quality-gates-final-code`.
- **Release permissions:** `POST_NOTIFICATIONS`, `VIBRATE`,
  `RECEIVE_BOOT_COMPLETED`, and the app-private
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  - INTERNET, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM and
    MANAGE/READ/WRITE_EXTERNAL_STORAGE are absent.

## Remaining store actions

1. Decide the identifiers, the first version and the Android backup
   policy.
2. Create the Android upload key and Apple distribution signing.
3. Physical Android is done except TalkBack: a human TalkBack pass on the
   CPH2707 (`docs/PHASE_8_5_PHYSICAL_ANDROID.md#talkback`). Run the
   physical runbook (`docs/PHASE_8.md#physical-runbook`) on an iPhone,
   including VoiceOver.
4. Publish the privacy policy with a contact address and the publisher's
   name.
5. Make the Play feature graphic. Capture the iPhone and iPad screenshots,
   and retake the Play ones after the version is final.
6. Fill in Play Data safety and the App Store privacy details.
7. Only on the owner's instruction: Play internal testing and TestFlight.
