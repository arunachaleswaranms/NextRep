# PROJECT_STATE

_Last updated: 2026-10-05. Phase 7 complete on its branch; PR open, not
merged._

**SOFTWARE RELEASE CANDIDATE: PASS · STORE SUBMISSION: MANUAL GATES
REMAIN**

## Repo

- Remote: https://github.com/arunachaleswaranms/NextRep (public)
- `main` baseline: `840ed50` (squash merge of PR #6, Phase 6). PRs #1–#6
  are Phases 1–6.
- Branch: `phase/7-release-readiness-and-premium-ux`, from `840ed50`
- Code HEAD qualified: `56f64d7`. This file and later doc-only commits
  follow it.
- PR: #7 (https://github.com/arunachaleswaranms/NextRep/pull/7), open for
  review, not merged
- CI: Flutter CI run 37318757893 on `56f64d7`: **green** (Format, analyze
  and test; Android builds and permission audit, which ran on the release APK)
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
- Brand assets: `flutter test tool/brand_assets/generate_brand_assets.dart`

## Versions

- Database schema: **v5** (unchanged in Phase 7)
- Backup `formatVersion`: **2** (reads 1 and 2; unchanged)
- App version: `1.0.0+1` (the scaffold value; release version not chosen)

## Results (final code)

| Gate | Result |
|---|---|
| format / analyze | clean / no issues |
| `flutter test` | **602 / 602** (566 at baseline) |
| Coverage | **93.3%** of handwritten lib (excluding `.g.dart` and the generated `schema_versions.dart`, as in Phase 6); 91.8% including it |
| Migrations v1 → v5 | 39 / 39 |
| Backup format 1 + 2 | 70 / 70 |
| Phase 7 suites | ticker 5, date edges 4, lifecycle 13, accessibility 14 |
| build_runner | no generated diff |
| Integration, emulator-5554 | **7 / 7** |
| Integration, iPhone 17 simulator | **7 / 7** (Phase 2 smoke re-run after its label fix) |
| `flutter build apk --debug` / `--release` | PASS / PASS (debug-signed) |
| `flutter build appbundle --release` | PASS (debug-signed, `CN=Android Debug`, **not uploadable**) |
| `flutter build ios --simulator` / `--release --no-codesign` | PASS / PASS |

## Devices

- **Android emulator (API 36), release build: PASS**
  - Cold launch 1.15 s.
  - Notification permission deny and allow.
  - Inexact alarms scheduled; a real reminder delivered.
  - Background and cold-start taps open the Journal.
  - The OS-revoked notice is shown with the preference kept.
  - DocumentsUI export; malformed and damaged files refused; restore with
    reminders off and no alarms left.
  - Adaptive icon and night splash checked; landscape is usable.
- **Physical Android: MANUAL REQUIRED.** CPH2707 wasn't connected this
  session; it last passed in Phase 6.
- **iOS simulator: PASS** (builds and 7/7 integration).
- **Physical iOS: MANUAL REQUIRED.** No iPhone available.

## Release configuration

- Android `applicationId` and iOS bundle id are both `com.nextrep.nextrep`.
  **PRODUCTION IDENTIFIER — USER DECISION REQUIRED**: it looks like the
  scaffold default and is permanent once published.
- Android signing: release uses the git-ignored `android/key.properties`
  when present, else the debug key. **ANDROID STORE SIGNING — NOT YET
  QUALIFIED.**
- iOS signing: **iOS RELEASE SIGNING — MANUAL REQUIRED.**
- Release permissions (aapt2): `POST_NOTIFICATIONS`, `VIBRATE`,
  `RECEIVE_BOOT_COMPLETED`, and the app-private
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  - INTERNET, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM and
    MANAGE/READ/WRITE_EXTERNAL_STORAGE are absent. CI audits this.

## Known debt / owner decisions

- Identifiers (above). Android system backup is still enabled (decide:
  keep it or `allowBackup="false"`).
- Manrope isn't bundled (the app uses platform fonts). iPad is enabled
  (needs screenshots). Phone landscape is cramped on the Journey.
- Unchanged from Phase 6:
  - no habit add or delete in a running arc
  - the clock-time Minimum Day policy
  - backups unencrypted by design
  - no merge-import
  - decoding on the UI isolate
  - reminders are inexact and pause after 14 idle days

## Exact recommended next step

Review and merge PR #7. Then run **Phase 8 as release execution**, not
features:

1. Decide the identifiers, the backup policy, the font, iPad support and
   the version.
2. Create the Android upload key and Apple signing.
3. Run the physical Android and iPhone passes (TalkBack, VoiceOver,
   delivery, Files / Drive, a profile frame check).
4. Capture the screenshots and publish the privacy policy.
5. Run Play internal testing and TestFlight.

Details: `docs/PHASE_7.md#phase-8-handoff`, `docs/RELEASE_CHECKLIST.md`.
