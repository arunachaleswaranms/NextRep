# Store readiness

> **Not current (Phase 9, 2026-10-08):** Google Play and App Store
> publication is not planned. NextRep is distributed as a signed APK on
> GitHub Releases ([DIRECT_DISTRIBUTION.md](DIRECT_DISTRIBUTION.md)). This
> document is kept as the Phase 7–8 record. Its open store gates are not
> project blockers.

Preparation notes for the Google Play and App Store listings, based on what
the app does as built (Phase 7, re-checked on the Phase 8 release build).
**Nothing has been submitted.** Google and
Apple make the final classification decisions. This document only records
what NextRep's code does, so the forms can be filled in accurately.

See [PRIVACY.md](../PRIVACY.md) for the user-facing privacy description,
[STORE_METADATA.md](STORE_METADATA.md) for listing copy and
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the release gates.

## Identifiers — OWNER DECISION REQUIRED

| Platform | Current value | Notes |
|---|---|---|
| Android `applicationId` | `com.nextrep.nextrep` | from `flutter create --org com.nextrep` |
| Android `namespace` | `com.nextrep.nextrep` | code namespace only; may differ from the id |
| iOS bundle identifier | `com.nextrep.nextrep` | `RunnerTests`: `com.nextrep.nextrep.RunnerTests` |

**FINAL IDENTIFIER DECISION — REQUIRED BEFORE STORE REGISTRATION.** The
owner was asked in Phase 8 and left it open, so nothing changed. These are not
`com.example.*` placeholders, but they look temporary:

- the doubled `nextrep.nextrep` is the Flutter scaffold default;
- reverse-DNS ids are normally based on a domain you control, and nothing in
  the repository shows ownership of `nextrep.com`.

Once published, a Play `applicationId` or an App Store bundle id can never
change. Pick the final ids (for example a reverse domain you own) before the
first upload. Phases 7 and 8 deliberately did **not** change them.

If they change, update all of these, then rerun every build and test gate:

- Android `applicationId` (and `namespace` plus the Kotlin package path
  only if wanted)
- iOS `PRODUCT_BUNDLE_IDENTIFIER` for Runner and RunnerTests
- the generated `<id>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
- the docs

## Versioning

- `pubspec.yaml`: `version: 1.0.0+1`. Android `versionName` / `versionCode`
  and iOS `CFBundleShortVersionString` / `CFBundleVersion` come from it.
- 1.0.0 is the scaffold's value, not a release decision. Choose the first
  public version when the manual gates below are done (for example
  `1.0.0+1` for the first upload). Every later upload needs a higher build
  number.
- **FIRST PUBLIC VERSION — OWNER DECISION REQUIRED**: left open in
  Phase 8. Set it once, near the end, then rebuild the APK, the AAB and
  iOS.

## Android / Google Play

| Item | Status |
|---|---|
| App category | Recommendation: **Health & Fitness**. Productivity also fits (habit tracking with no health data). |
| Data collection | **No data collected or shared** by the developer. Nothing leaves the device through the app: no `INTERNET` permission, no SDKs that send data. |
| Ads | None. |
| Account requirement | None. No sign-in. |
| Target audience | General audience. Not designed for children. |
| Permissions | `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED` and the app-private AndroidX receiver permission (see below). |
| Notification permission | Asked only when the user turns a reminder on (Android 13+). The app works fully without it. |
| Backup / document picker | Export and restore go through the Storage Access Framework (system document UI). No storage permission. |
| `INTERNET` | **Absent** from the release build (debug/profile only, for Flutter tooling). Audited in CI. |
| Exact alarms | Not used (`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` absent). Reminders are inexact. |
| Android system backup | `allowBackup` is unset (so enabled): Android Auto Backup / device transfer may include the app database if the user has system backup on. Google's backup service, not the app, handles this. **OWNER DECISION REQUIRED** (left open in Phase 8). Keep it: data survives a phone change, and PRIVACY.md already says so. Or set `android:allowBackup="false"`, add `dataExtractionRules` if targetSdk 36 needs them, update PRIVACY.md and re-test install and upgrade. |
| Privacy policy | **Required** by Play for every app. [PRIVACY.md](../PRIVACY.md) is the source text; it still needs a public URL and a contact address. |
| Screenshots | 8 draft phone screenshots (1080 × 2160) captured from synthetic data in Phase 8, not uploaded. See [STORE_METADATA.md](STORE_METADATA.md#screenshots). Retake them once the version is final. |
| App icon | 512 × 512 PNG ready: `assets/branding/store/play_store_icon_512.png` (generated, opaque). |
| Feature graphic | 1024 × 500, **MANUAL STORE ASSET** (concept in STORE_METADATA.md). |
| Signing | **ANDROID STORE SIGNING — MANUAL REQUIRED.** No upload key exists. Phase 8's APK and AAB are signed with `CN=Android Debug` and aren't uploadable. See [ANDROID_SIGNING.md](ANDROID_SIGNING.md). Use Play App Signing. |
| Format | Upload the AAB (`flutter build appbundle --release`). |
| SDK levels | `minSdk` 24, `targetSdk` 36, `compileSdk` 36 (Flutter 3.47 defaults). targetSdk 36 meets Play's current target-level requirement. |

### Release build permissions (aapt2, Phase 8 release APK, unchanged since Phase 7)

```
uses-permission: android.permission.RECEIVE_BOOT_COMPLETED
uses-permission: android.permission.VIBRATE
uses-permission: android.permission.POST_NOTIFICATIONS
permission:      com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

`android.permission.DUMP` appears in the merged manifest only as the
`android:permission` guard on AndroidX's `ProfileInstallReceiver`, which
limits who may *call* that receiver to the shell. It is not requested by
the app.

### Data safety form: expected answers (verify when filling in)

- Does the app collect or share any of the required user data types? **No.**
- Is all user data encrypted in transit? Not applicable: no data is
  transmitted.
- Can users request deletion? Data never reaches the developer. Users can
  delete arcs in the app or uninstall it.

## iOS / App Store

| Item | Status |
|---|---|
| Data collection (privacy nutrition label) | Expected: **Data Not Collected**. No data is sent off the device by the app, and there are no third-party SDKs that collect data. |
| Tracking | None. No IDFA, no App Tracking Transparency prompt needed. |
| Account requirement | None. |
| Notifications | Local only (`UNUserNotificationCenter` through `flutter_local_notifications`). Permission is requested when a reminder is turned on. No push, so no `aps-environment` entitlement. |
| Document picker | `UIDocumentPickerViewController` (export and import) through `file_picker`. No photo-library or file-system entitlements. |
| Info.plist privacy strings | None required: no camera, microphone, photos, location, contacts, health or tracking access. |
| Capabilities | None added. No HealthKit, background modes, push or app groups. |
| Display name | `NextRep` (`CFBundleDisplayName`). |
| Deployment target | iOS 15.0. |
| Orientations | iPhone: portrait and both landscape orientations. iPad: all four. The layouts scroll in landscape. |
| Icons | Every `AppIcon` size generated, opaque RGB (no alpha), 1024 marketing icon included. |
| Launch screen | Night background with the NextRep mark (`LaunchScreen.storyboard`). |
| Screenshots | **Not captured.** A 6.9" (or 6.7") iPhone set is required, and an iPad 13" set too while iPad support stays enabled (it is). Use the same synthetic backup. |
| iCloud / device backup | App data is included in the user's iCloud and computer device backups (iOS default). Describe this in the privacy policy. |
| Export compliance | The app uses no encryption beyond the OS's own. SHA-256 is used only as a checksum. Expected answer: exempt; set `ITSAppUsesNonExemptEncryption` = NO when confirming. |
| Signing / provisioning | **IOS STORE SIGNING — MANUAL REQUIRED.** No `DEVELOPMENT_TEAM` is set, so a physical iPhone can't install the app yet. `flutter build ios --release --no-codesign` builds. Distribution needs an Apple Developer account, a team, a distribution certificate and an App Store provisioning profile for the final bundle id. None of these are configured. |

## Manual store steps (still open after Phase 8)

1. Decide the production identifiers (Android and iOS).
2. Decide whether Android system backup stays enabled; reflect it in the
   policy.
3. Create the Android upload key; configure `key.properties` locally.
4. Enrol in Apple Developer; set up signing for the final bundle id.
5. Publish the privacy policy at a public URL, with a contact address.
6. Capture the iPhone (and iPad) screenshots; make the Play feature
   graphic.
7. Run the physical-device gates in the release checklist. No physical
   Android or iPhone was available in Phase 8; the runbook is in
   [PHASE_8.md](PHASE_8.md#physical-runbook).
8. Fill in Play Data safety and App Store privacy details from this
   document.
9. Choose the release version and build number.
