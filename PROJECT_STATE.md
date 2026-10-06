# PROJECT_STATE

_Last updated: 2026-10-06. Phase 8 complete on its branch; PR open, not
merged._

**SOFTWARE RELEASE CANDIDATE: PASS · STORE SUBMISSION: MANUAL GATES
REMAIN**

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `57a3c13` (squash merge of PR #7, Phase 7). PRs #1–#7
  are Phases 1–7.
- Branch: `phase/8-store-launch-and-physical-qualification`, from `57a3c13`
- Code HEAD qualified: `7ebd644` (fixes); `9b86821` adds the dev-only
  screenshot tool. Later commits are docs only.
- PR: see the Phase 8 pull request (open for review, not merged)
- CI: recorded on the PR
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
| `flutter test` | **604 / 604** (602 at baseline) |
| Coverage | **93.3%** handwritten lib (91.8% including `schema_versions.dart`) |
| Migrations / backup 1+2 / release qualification | 39 / 70 / 38 |
| Integration: emulator-5554 / iPhone 17 simulator | **7 / 7** / **7 / 7** |
| APK debug / release, AAB | PASS (release and AAB debug-signed, `CN=Android Debug`, **not uploadable**) |
| iOS simulator / release no-codesign | PASS / PASS |

## Devices

- **Physical Android: MANUAL REQUIRED.** No device appeared in adb this
  session.
- **Emulator (API 36), release build: PASS.** Covered:
  - in-place upgrades from v5 data and from a Phase 5 (v4) release
  - fresh install and the core flow
  - notifications (deny, allow, delivery, background and cold-start taps,
    revocation)
  - DocumentsUI export and restore, corrupt copies refused
  - 2× text, "Remove animations", icons and splash
- **TalkBack: MANUAL REQUIRED.** adb input bypasses TalkBack's gestures.
  The node tree was checked instead.
- **Physical iOS: MANUAL REQUIRED** (none connected), and install is
  blocked by signing. **VoiceOver: MANUAL REQUIRED.**
- Found and fixed (all P2): the level row cut short at 2×, "1 reflections",
  and a doubled spoken period. No P0 or P1.

## Release configuration

- **Identifiers:** `com.nextrep.nextrep` on both platforms. **FINAL
  IDENTIFIER DECISION — REQUIRED BEFORE STORE REGISTRATION.**
- **Android system backup:** enabled (`allowBackup` unset). **OWNER
  DECISION REQUIRED.**
- **Android signing:** no `key.properties`. **ANDROID STORE SIGNING —
  MANUAL REQUIRED.**
- **iOS signing:** no team. **IOS STORE SIGNING — MANUAL REQUIRED.**
- **QA artifact hashes:** `docs/PHASE_8.md#android-signing-and-artifacts`.
- **Release permissions:** `POST_NOTIFICATIONS`, `VIBRATE`,
  `RECEIVE_BOOT_COMPLETED`, and the app-private
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  - INTERNET, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM and
    MANAGE/READ/WRITE_EXTERNAL_STORAGE are absent.

## Remaining store actions

1. Decide the identifiers, the first version and the Android backup
   policy.
2. Create the Android upload key and Apple distribution signing.
3. Run the physical runbook (`docs/PHASE_8.md#physical-runbook`) on the
   CPH2707 and an iPhone, including TalkBack and VoiceOver.
4. Publish the privacy policy with a contact address and the publisher's
   name.
5. Make the Play feature graphic. Capture the iPhone and iPad screenshots,
   and retake the Play ones after the version is final.
6. Fill in Play Data safety and the App Store privacy details.
7. Only on the owner's instruction: Play internal testing and TestFlight.
