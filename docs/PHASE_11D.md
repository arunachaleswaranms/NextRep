# Phase 11D: About screen and manual update check

## Objective

Add an **About NextRep** screen (identity, the installed version and build,
privacy, the official source, open-source licenses) and, on Android, a
**manual "Check for updates"** that reads the official repository's latest
published GitHub Release.

The product promise: **NextRep never checks for updates by itself.** It
contacts GitHub only when the user taps Check for updates: one request per
tap, never at install, startup, resume, on opening About, on a date change,
in the background, from WorkManager, reminders, Hydration Coach, Focus
Guard, backup or restore.

This is the first phase allowed to add Android's `INTERNET` permission, and
only for that button. Version stays **1.1.0+2**, schema **v6**, backup
format **3**. Nothing was tagged or published, and no APK was distributed.
Phases 11E and 11F were not started.

## Baseline

| | |
|---|---|
| `origin/main` | `32bd3c2c1781875ff3eefdff9ab8f668931cc57c` (squash merge of PR #17, Phase 11C), fetched and verified before any change |
| Merged | PR #15 (11A), PR #16 (11B), PR #17 (11C); main CI green (run 38616174292) |
| Published | GitHub Release `v1.1.0` (latest), `v1.0.0` |
| Branch | `phase/11d-about-manual-updates` from `32bd3c2`, in a separate worktree without `android/key.properties` |
| Version / `appVersion` / schema / backup | `1.1.0+2` / `1.1.0` / v6 / write 3, read 1 + 2 + 3 |
| `flutter test` / native JVM | 976 / 976 / 67 / 67 |
| Release permissions | `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `PACKAGE_USAGE_STATS`, `WAKE_LOCK`, app-private receiver permission; `INTERNET` forbidden by CI and the release script |

## Implementation

### Layers

| Layer | File | Role |
|---|---|---|
| Domain | `lib/domain/update/release_version.dart` | `ReleaseVersion`: strict `MAJOR.MINOR.PATCH` parse, numeric comparison |
| Domain | `lib/domain/update/official_source.dart` | the official owner, repository, API endpoint and pages; URL validation |
| Domain | `lib/domain/update/github_release.dart` | `PublishedRelease.parse`: field-by-field validation of GitHub's JSON |
| Domain | `lib/domain/update/release_feed.dart` | `ReleaseFeed` transport interface, `ReleaseFeedResponse`, transport errors |
| Domain | `lib/domain/update/update_checker.dart` | `UpdateChecker`: one fetch → one explicit `UpdateCheckResult` |
| Domain | `lib/domain/update/installed_app.dart` | `InstalledApp` (version, build) and its source interface |
| Data | `lib/data/github_release_feed.dart` | `GitHubReleaseFeed` over `package:http` (the only HTTP code in the app) |
| Data | `lib/data/platform_app_info.dart` | installed version and build through `package_info_plus` |
| Data | `lib/data/external_links.dart` | opens allow-listed official pages through `url_launcher`, external browser only |
| App | `lib/app/dependencies.dart` | `installedAppSourceProvider`, `releaseFeedProvider` (**null by default**), `externalLinksProvider` |
| App | `lib/main.dart` | provides `GitHubReleaseFeed()` **on Android only** |
| Feature | `lib/features/about/` | `AboutScreen`, `UpdateCheckController` (+ `installedAppProvider`), `AboutButton` / `AboutLink` |

The domain has no `http` or `dart:io` dependency; tests replace the
transport (`FakeGitHubClient`), the version source and the browser.

`releaseFeedProvider` follows Focus Guard's pattern: null unless `main.dart`
provides it, which it does only on Android. On iOS, and in every test that
doesn't supply a fake, no network-capable object exists at all.

### Installed version and build

About shows `Version <versionName>` and `Build <versionCode>` read from the
installed package through `package_info_plus` (Android `PackageManager`,
iOS `Info.plist`), never from `appVersion`. `appVersion` keeps its role:
written into backups, and kept equal to `pubspec.yaml` by a test. If the
metadata can't be read, About says "Version information is unavailable."
and disables the check rather than showing a stale constant. For this
source: **Version 1.1.0, Build 2**.

## About screen and navigation

Route `AppRoutes.about = '/settings/about'`, a root-level `GoRoute`.
`AppRoutes.redirect` never redirects it (tested for no arc, setup only,
active, completed, completed + setup, and before resolution).

Sections: ABOUT NEXTREP (NEXTREP, "Every rep counts.", the companion line
and a short explanation), YOUR VERSION, UPDATES, PRIVACY, OFFICIAL SOURCE
(repository, Open on GitHub, Open-source licenses). Winter tokens and
`WinterCard`s, no animation or celebration.

| State | Entry point |
|---|---|
| Active Arc | History tab header: ⓘ "About NextRep" beside Focus Guard and Data & Backup |
| Completed Arc (home) | summary: "About NextRep" under Arc History |
| Standalone Arc History | app bar: ⓘ "About NextRep" beside Focus Guard and Data & Backup |
| First install | onboarding: "About NextRep" under the three points (in the scrolling part, so Let's Begin stays put) |
| Setup | end of the habit list: "About NextRep"; setup is saved as it is edited, so pushing About and coming back loses nothing |

All are `context.push`, so Back returns to where the user was. No
existing entry (Focus Guard, Data & Backup, Insights, Reminders) moved or
was hidden. From About, "Back up your data" opens Data & Backup.

## Manual networking contract

| Event | GitHub requests |
|---|---|
| Constructing providers, the feed, the checker or the controller | 0 |
| Launch, Today | 0 |
| Resume, local midnight, a later date | 0 |
| Focus Guard on (its reconciliation and WorkManager scheduling) | 0 |
| Hydration Coach reconciliation | 0 |
| Restore (including the app restart) | 0 |
| Opening, rebuilding (resize, text scale, resume) or leaving About | 0 |
| Reopening About | 0; the screen is Idle again |
| **Tap "Check for updates"** | **exactly 1** |
| Rebuilds, repeated taps, or a direct `check()` while one is in flight | 0 more |
| Leaving and reopening About while one is in flight, then tapping again | 0 more: the tap joins the running request |
| Tapping again after it finished | exactly 1 more |
| View official release / Open on GitHub / licenses | 0 (browser or in-app page) |

Each line is asserted in `test/features/phase11d_about_flow_test.dart` by
counting the requests the real controller, checker and feed send to a fake
transport. `test/app/network_boundary_test.dart` adds a static check: only
`github_release_feed.dart` imports `package:http` or names `HttpClient`;
only `main.dart` constructs the feed; only the checker fetches; only the
About screen calls the controller; no Kotlin source uses a network API;
`badCertificateCallback` appears nowhere.

`GitHubReleaseFeed` is single-flight: a fetch made while one is pending
returns the same future, so leaving About during a check, reopening it and
tapping again can't start a second concurrent request (found by an
independent review of this branch, fixed and tested).

`UpdateCheckController` is `autoDispose` and watched by the About screen
itself: the state lives exactly while About is open (it survives the card
being scrolled away), and nothing is persisted. A request still running when
About closes completes or times out and its result is dropped
(`ref.mounted`), with no setState-after-dispose.

## GitHub API request

```
GET https://api.github.com/repos/arunachaleswaranms/NextRep/releases/latest
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: NextRep-Manual-Updates
```

No body, credentials, token, cookie or identifier. GitHub's `latest`
returns the most recent **published full release** (never a draft or
prerelease) and 404 when there is none.

Transport limits (`GitHubReleaseFeed`):

- a new client for each check, closed afterwards (closing also aborts a
  request still running at the timeout)
- **10 s** for the whole exchange, connecting included; no indefinite
  spinner
- **256 KiB** body limit, enforced on the declared length and while
  streaming (the real v1.1.0 response is about 11.5 KB); the decompressed
  stream is what is counted
- `followRedirects = false`: a 3xx is returned, never followed
- the platform's TLS validation, unmodified
- transport errors keep only their type; no response body is ever logged
  (release builds log nothing at all)
- no retries, no cache, no persistence; never downloads assets, APKs or
  checksum files

## Release validation

`PublishedRelease.parse` accepts a release only if:

- the body is UTF-8 JSON and an object, served as `application/json` or
  `application/vnd.github+json`
- `tag_name` is a string and a stable `vMAJOR.MINOR.PATCH` tag
- `draft` and `prerelease` are present and exactly `false`
- `html_url` is `https://github.com/arunachaleswaranms/NextRep/releases/tag/<tag_name>`:
  https, host `github.com`, no port, credentials, query or fragment;
  owner and repository compared case-insensitively, as GitHub treats them
- `assets` is a list of objects with string names; an official Android
  asset must be served from
  `https://github.com/arunachaleswaranms/NextRep/releases/download/<tag>/<name>`

The browser destination is **built** by `OfficialSource.releasePage` from
the validated version, never copied from the response.
`SystemExternalLinks` opens only `OfficialSource.isTrustedPage` URLs (the
repository, its releases, a stable tag page), in an external application.
Release notes are ignored: nothing is rendered, and url_launcher's in-app
`WebViewActivity` is removed from the manifest.

### Versions

`ReleaseVersion` parses `^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$`
after a length check (24 characters): no prerelease or build suffix, no
leading zeros, signs, spaces or other digits, at most six digits a part, so
nothing can overflow. Comparison is numeric, part by part (`1.10.0 > 1.9.9`,
`2.0.0 > 1.99.99`). The installed **version name** is compared, never the
build number.

### Official Android assets

For release `vX.Y.Z`: `NextRep-vX.Y.Z-android.apk` and
`NextRep-vX.Y.Z-android.apk.sha256`, both with `state: "uploaded"` and a
positive integer `size`. Names are matched exactly. Nothing is downloaded or
inspected.

## Result states

| State | When | Copy |
|---|---|---|
| Idle | About opened | "Only checks GitHub when you tap." |
| Checking | in flight; button disabled, spinner | "Checking for updates…" / "Checking…" |
| Up to date | latest == installed | "You're using the latest published version." + "Latest published: v1.1.0" |
| Update available | latest > installed, APK + checksum uploaded | "NextRep v1.2.0 is available." + installed / available, **View official release** |
| Release not ready | latest > installed, assets missing or not uploaded | "A newer release is listed, but its Android download is not ready yet." |
| Newer build installed | latest < installed | "This build is newer than the latest published release." |
| No published release | 404 | "GitHub did not return a published NextRep release." |
| Network failure | offline, DNS, refused, TLS failure, timeout | "Couldn't check for updates." + "Check your connection and try again." |
| Rate limited | 429, or 403 with `x-ratelimit-remaining: 0` or `retry-after` | "GitHub is temporarily limiting update checks. Please try again later." |
| GitHub unavailable | 5xx, another 403, any other status | "GitHub couldn't answer the update check. Please try again later." |
| Invalid release | redirect, wrong content type, not JSON, too large, draft, prerelease, bad tag, unofficial URL, malformed assets | "Couldn't verify the latest release information. Please try again later." |

"GitHub unavailable" was added to the suggested list so a 503 isn't
reported as a connection problem. No failure is ever shown as up to date,
and no raw error text reaches the screen. A browser that can't open shows
"Couldn't open a browser. Visit github.com/arunachaleswaranms/NextRep/releases
in your browser."

The update guidance on Android: "Updates are published on the official
NextRep GitHub Releases page." / "Install a newer signed APK over your
current app to keep your data." / "Don't uninstall NextRep to update.",
and a "Back up your data" link.

### iOS

No feed is provided on iOS, so the check isn't offered: About shows the
version and build and "NextRep releases are published for Android only, so
this device doesn't check for updates." No APK wording, no entitlements,
URL schemes, background modes or `Info.plist` changes.

## Android permissions

`AndroidManifest.xml` adds exactly `android.permission.INTERNET`, with a
comment limiting it to the manual check, and removes
`io.flutter.plugins.urllauncher.WebViewActivity` (`tools:node="remove"`).
No `<queries>` were added (url_launcher's `launchUrl` doesn't need one),
so Focus Guard's launcher-only visibility is unchanged. The Focus Guard
provider stays non-exported and WorkManager's foreground service and
network-state permission stay removed.

package_info_plus, http and url_launcher add no permission (checked in the
merged release manifest below).

## CI and release script

`.github/workflows/flutter-ci.yml` and
`tool/release/prepare_android_release.sh`:

- `INTERNET` moved from the forbidden list into the **exact** expected set
- still forbidden: `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
  `QUERY_ALL_PACKAGES`, `REQUEST_INSTALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`,
  `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, storage, media, contacts,
  accounts, camera, microphone; Accessibility / VPN / notification-listener
  services; foreground services
- new: an in-app `WebViewActivity` fails the audit
- kept: the Focus Guard provider check, the R8 constructor checks, and in
  the script the clean-tree, signer, package, version, checksum and staging
  checks
- CI runs a new focused step: version, release-validation, transport, About
  flow, network-boundary and route tests

## Privacy impact

PRIVACY.md, README.md and DIRECT_DISTRIBUTION.md no longer say the current
source has no network access. They now say: NextRep works offline and never
goes online by itself; tapping Check for updates sends one HTTPS request to
GitHub that carries none of the user's NextRep data; GitHub receives normal
request metadata such as the IP address (not anonymous); release pages open
in the browser under GitHub's own practices; nothing about checks is stored;
nothing in the app depends on whether the user ever checks.

Published v1.0.0 and v1.1.0 still had no `INTERNET` permission. Their
release notes (`docs/releases/`) and the historical store documents were
left as written.

## Test evidence

All on the final branch code, locally (macOS, Flutter 3.47.5 / Dart 3.13.4):

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 297 files, 0 changed |
| `flutter analyze` | no issues |
| `flutter test` | **1144 / 1144** (baseline 976; +168, none removed or skipped) |
| `./gradlew :app:testDebugUnitTest` | **67 / 67** native JVM tests (unchanged) |
| Migrations v1 → v6 | 52 / 52 |
| Backup formats (write 3; read 1, 2, 3) | 90 / 90 |
| Focus Guard suite | 104 / 104 |
| Hydration and reminders (planner, service, reminders, 11B flow) | 82 / 82 |
| Achievements, share cards, Phase 5 routes | 100 / 100 |
| Release qualification (day change, date edges, lifecycle, accessibility) | 39 / 39 |
| Manual update check suite (CI step) | 182 / 182 |

New tests (168):

| File | Tests | Covers |
|---|---|---|
| `test/domain/release_version_test.dart` | 54 | numeric comparison (1.10.0 > 1.9.9, 2.0.0 > 1.99.99, …), stable tags, 36 malformed tags (empty, `v`, `v1`, `v1.2`, `1.2`, `-beta`, `-rc.1`, `+3`, separators, negatives, leading zeros, full-width digits, oversized parts and strings) |
| `test/domain/update_checker_test.dart` | 52 | release parsing (draft, prerelease, missing / wrong-typed fields, 19 bad `html_url`s, assets missing / not uploaded / unsized / foreign, HTML, empty, invalid UTF-8), every status (200, 3xx, 403 ± rate-limit headers, 404, 429, 5xx), canonical page, `OfficialSource.isTrustedPage` |
| `test/data/github_release_feed_test.dart` | 18 | exact request (GET, URL, three headers, no body, no redirects), a client per request and always closed, single-flight, size limit (declared and streamed, endless body), timeout (headers and stalled body), socket / DNS / client / HTTP / TLS errors, no error text kept |
| `test/features/phase11d_about_flow_test.dart` | 39 | the manual-networking table above over the real controller and feed; 15 result states with their copy; retry by tap; timeout; View official release and Open on GitHub; failed browser; licenses; installed metadata and unreadable metadata; iOS; 320 × 568 at 2× text; scrolled card keeps a running check; tap-target, label, header and live-region checks; every entry point and Back, with Arc data unchanged |
| `test/app/network_boundary_test.dart` | 4 | the static network boundary (complements, doesn't replace, the runtime tests) |
| `test/app/app_routes_test.dart` | +1 | `/settings/about` never redirected |

`integration_test/phase11d_about_smoke_test.dart` runs on a device or
simulator with the real `package_info_plus` (iOS evidence below). It is not
run on the Android emulator: `flutter test -d <emulator>` installs a
debug-signed `com.nextrep.nextrep`, which must never meet the official
install.

The tap-hit-test warning printed by `phase4_flow_test.dart` also appears in
main's CI run 38616174292; it predates this phase.

## Android qualification

Release APK audit (`aapt2`, `apkanalyzer`, `apksigner`) of the merged
release build, `com.nextrep.nextrep` 1.1.0 (2), debug-signed in the
worktree (no `key.properties`, so it can never pass as an official update):

| Check | Result |
|---|---|
| Permissions, exactly | `INTERNET`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `PACKAGE_USAGE_STATS`, `WAKE_LOCK`, `com.nextrep.nextrep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| Absent | `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`, `QUERY_ALL_PACKAGES`, `REQUEST_INSTALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `MANAGE/READ/WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_IMAGES/VIDEO/AUDIO`, `READ/WRITE_CONTACTS`, `GET_ACCOUNTS`, `CAMERA`, `RECORD_AUDIO` |
| Services | no Accessibility, VPN or notification-listener service; no `SystemForegroundService` or `foregroundServiceType`; no `WebViewActivity` |
| Focus Guard provider | present, `exported=false` |
| `<queries>` | unchanged: `PROCESS_TEXT`, launcher `MAIN/LAUNCHER`, and file_picker's `GET_CONTENT` (pre-existing); url_launcher adds none |
| R8 (minified) | `WorkDatabase_Impl <init>()`, `FocusGuardWorker <init>(Context, WorkerParameters)`, `FocusGuardCheckProvider <init>()` kept |

**API 36 emulator** (`emulator-5554`, `sdk_gphone64_arm64`), 15 Oct 2026.
The official signed v1.1.0 installed there (versionCode 2, first installed
2026-10-12 22:38:38, updated 22:39:16) was recorded first and never
touched: the qualification build was the **minified release build** under a
temporary, uncommitted `applicationIdSuffix ".qualification"`, installed
beside it, uninstalled afterwards, and the official install's record was
identical after. Network use was measured from Android's own per-UID
accounting (`dumpsys netstats --poll`, then the UID's bytes) after every
step.

| Step | App UID bytes (rx / tx) |
|---|---|
| Install: `INTERNET` granted at install, **no permission dialog** | 0 / 0 |
| Cold launch → onboarding (with "About NextRep") | 0 / 0 |
| About from onboarding: **Version 1.1.0, Build 2**, Idle | 0 / 0 |
| 20 s on About; Back; reopen; Home and resume on About | 0 / 0 |
| **Tap Check for updates** (live GitHub): "You're using the latest published version. Latest published: v1.1.0" | 9,204 / 1,015 |
| 20 s idle afterwards | unchanged |
| Tap again (one more check, same result) | 18,419 / 1,990 |
| Airplane mode, tap: "Couldn't check for updates. Check your connection and try again." | unchanged |
| Network back, tap again: up to date | 27,635 / 2,965 |
| Open on GitHub: Chrome opened in its own task (external app, not a WebView) | unchanged |
| Back from Chrome → About; no APK in Downloads, no package installer | unchanged |
| New Arc → setup; English Practice switched on; About from setup; Back: setup intact (5 habits) | unchanged |
| Start → Today (Day 1 of 92), Water logged, History tab: Focus Guard, Data & Backup, About, Insights | unchanged |
| About from History: Idle again (nothing persisted) | unchanged |
| Focus Guard: Usage Access granted, Chrome chosen, on; notification prompt (Focus Guard's own, as in 11C); WorkManager ran its check in the `:focus_guard` process | unchanged |
| Hydration Coach on (Balanced, 08:00–20:00): nudges scheduled as local alarms | unchanged |

Every byte the app sent came from the three taps on Check for updates.
"Update available" was not exercised against GitHub (v1.2.0 isn't
published, and no fake release was published); it is covered by the
widget tests with a synthetic v1.2.0. **Physical device: not connected**
(the OnePlus wasn't attached), so no physical qualification was done in
this phase; the signed physical upgrade belongs to Phase 11F.

## iOS qualification

| Check | Result |
|---|---|
| `flutter build ios --simulator` | PASS |
| `flutter build ios --release --no-codesign` | PASS (22.3 MB) |
| `integration_test/phase11d_about_smoke_test.dart` on the iPhone 17 simulator (booted) | PASS: onboarding → About shows **Version 1.1.0, Build 2** from the real `Info.plist`; no Check for updates; "NextRep releases are published for Android only…"; Back to onboarding; no exception |
| `ios/` changes | none (no entitlements, URL schemes, background modes or `Info.plist` keys) |

No feed is constructed on iOS, so no GitHub request can be made there at
all.

## Known limitations

- The check is a metadata lookup. It says a release exists; the checksum
  and certificate checks in DIRECT_DISTRIBUTION.md remain how a download is
  verified.
- GitHub allows 60 unauthenticated API requests an hour per IP address.
  Exceeding it (shared networks) shows "temporarily limiting".
- A captive portal or TLS-intercepting proxy shows as a connection problem
  (TLS failure) or an invalid release (HTML), never as up to date.
- If the repository were ever renamed, GitHub would answer with a redirect,
  which is reported as an invalid release by design.

## Deferred

- Phase 11E: integration and regression qualification of the v1.2 line.
- Phase 11F: version bump, signed APK, physical upgrade, tag and release.
  The physical signed-upgrade path, and the first real "update available"
  (v1.1.0 → v1.2.0), belong there.

## PR

[#18](https://github.com/arunachaleswaranms/NextRep/pull/18), "Phase 11D:
add About screen and manual update checking", from
`phase/11d-about-manual-updates` into `main`. Open for independent review;
not merged. The final head's CI run is recorded in the PR.
