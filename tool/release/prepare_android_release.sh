#!/usr/bin/env bash
# Builds and verifies the signed Android release APK for GitHub
# distribution, and stages it with its SHA-256 checksum:
#
#   build/release-candidate/NextRep-v<version>-android.apk
#   build/release-candidate/NextRep-v<version>-android.apk.sha256
#
# Run from the repository root on the owner's machine, with the permanent
# release key configured in android/key.properties (docs/ANDROID_SIGNING.md):
#
#   tool/release/prepare_android_release.sh
#
# It never reads or prints signing passwords, creates keys, changes the
# version, tags, pushes or uploads anything. Gradle reads key.properties.
#
# Environment:
#   EXPECTED_CERT_SHA256  signer certificate SHA-256 the APK must carry
#                         (defaults to the NextRep release certificate;
#                         set it to your own when building a fork)
#   ANDROID_HOME          Android SDK (defaults to ~/Library/Android/sdk)
#   SKIP_CHECKS=1         skip format/analyze/tests (verification still runs)
set -euo pipefail

readonly APPLICATION_ID="com.nextrep.nextrep"
readonly NEXTREP_CERT_SHA256="65b70cd096d1bbf2c0f50ee02f4b55974625cc4cdbead739225f0675afc8f0ba"
readonly EXPECTED_CERT="${EXPECTED_CERT_SHA256:-$NEXTREP_CERT_SHA256}"
# Exactly these permissions, nothing else: INTERNET for the manual update
# check (About; one request to GitHub, only when the user taps), local
# reminders (boot, vibrate, notifications, the app-private receiver
# permission), Focus Guard's Usage Access (PACKAGE_USAGE_STATS, which the
# user grants in system settings) and WorkManager's WAKE_LOCK for its
# periodic check.
readonly EXPECTED_PERMISSIONS="android.permission.INTERNET \
android.permission.RECEIVE_BOOT_COMPLETED \
android.permission.VIBRATE android.permission.POST_NOTIFICATIONS \
android.permission.PACKAGE_USAGE_STATS android.permission.WAKE_LOCK \
${APPLICATION_ID}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
# Named as well, so a failure says why: exact alarms, storage and media,
# contacts and accounts, camera, microphone, every-package visibility,
# overlays, installing packages, foreground services and network state
# (WorkManager's, removed in the manifest).
readonly FORBIDDEN_PERMISSIONS="SCHEDULE_EXACT_ALARM USE_EXACT_ALARM \
MANAGE_EXTERNAL_STORAGE READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE \
READ_MEDIA_IMAGES READ_MEDIA_VIDEO READ_MEDIA_AUDIO READ_MEDIA_VISUAL_USER_SELECTED \
READ_CONTACTS WRITE_CONTACTS GET_ACCOUNTS CAMERA RECORD_AUDIO \
QUERY_ALL_PACKAGES SYSTEM_ALERT_WINDOW REQUEST_INSTALL_PACKAGES FOREGROUND_SERVICE \
ACCESS_NETWORK_STATE"
# No service bound by these may be declared at all.
readonly FORBIDDEN_BINDS="BIND_ACCESSIBILITY_SERVICE BIND_VPN_SERVICE \
BIND_NOTIFICATION_LISTENER_SERVICE"
readonly BUILT_APK="build/app/outputs/flutter-apk/app-release.apk"
readonly STAGING_DIR="build/release-candidate"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cd "$(git rev-parse --show-toplevel)"

[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
[[ -f android/key.properties ]] ||
  fail "android/key.properties is missing; release builds would be debug-signed"

version_line="$(grep -E '^version: ' pubspec.yaml)"
version="${version_line#version: }"
version_name="${version%%+*}"
version_code="${version##*+}"
[[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$version_code" =~ ^[0-9]+$ ]] ||
  fail "pubspec version '$version' is not <major>.<minor>.<patch>+<code>"
readonly ARTIFACT="NextRep-v${version_name}-android.apk"

sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
build_tools="$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
[[ -n "$build_tools" ]] || fail "no Android build-tools under $sdk"
readonly APKSIGNER="${build_tools}apksigner"
readonly AAPT2="${build_tools}aapt2"
readonly APKANALYZER="${sdk}/cmdline-tools/latest/bin/apkanalyzer"
[[ -x "$APKANALYZER" ]] || fail "apkanalyzer not found under $sdk/cmdline-tools/latest"

echo "== NextRep v${version_name} (${version_code}) at $(git rev-parse --short HEAD)"

if [[ "${SKIP_CHECKS:-}" != "1" ]]; then
  echo "== Quality gates"
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test
fi

echo "== Build"
flutter build apk --release

# Verifies one APK file: signer, identity, version, permissions and
# declared components.
verify_apk() {
  local apk="$1" certs badging permissions forbidden declared expected manifest bind
  echo "== Verify $apk"

  certs="$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null)" ||
    fail "apksigner could not verify $apk"
  grep -q "CN=Android Debug" <<<"$certs" && fail "$apk is signed with the Android debug key"
  [[ "$(grep -c '^Signer #[0-9]* certificate DN' <<<"$certs")" == "1" ]] ||
    fail "$apk must have exactly one signer"
  grep -q "certificate SHA-256 digest: ${EXPECTED_CERT}$" <<<"$certs" ||
    fail "$apk signer is not the expected certificate ${EXPECTED_CERT}"
  grep -E "certificate (DN|SHA-256 digest)" <<<"$certs"

  badging="$("$AAPT2" dump badging "$apk")"
  grep -q "^package: name='${APPLICATION_ID}' versionCode='${version_code}' versionName='${version_name}'" <<<"$badging" ||
    fail "$apk is not ${APPLICATION_ID} ${version_name} (${version_code})"
  grep -E "^package:|SdkVersion:|^application-label:" <<<"$badging"

  permissions="$("$AAPT2" dump permissions "$apk")"
  echo "$permissions"
  for forbidden in $FORBIDDEN_PERMISSIONS; do
    grep -q "android.permission.${forbidden}'" <<<"$permissions" &&
      fail "$apk requests android.permission.${forbidden}"
  done
  declared="$(sed -nE "s/^uses-permission(-sdk-23)?: name='([^']*)'.*/\2/p" <<<"$permissions" | sort -u)"
  expected="$(tr ' ' '\n' <<<"$EXPECTED_PERMISSIONS" | sed '/^$/d' | sort -u)"
  [[ "$declared" == "$expected" ]] ||
    fail "$apk permissions differ from the expected set:"$'\n'"$(diff <(echo "$expected") <(echo "$declared"))"

  manifest="$("$AAPT2" dump xmltree --file AndroidManifest.xml "$apk")"
  for bind in $FORBIDDEN_BINDS; do
    grep -q "android.permission.${bind}" <<<"$manifest" &&
      fail "$apk declares a service guarded by ${bind}"
  done
  grep -qE "SystemForegroundService|foregroundServiceType" <<<"$manifest" &&
    fail "$apk declares a foreground service"
  grep -q "WebViewActivity" <<<"$manifest" &&
    fail "$apk declares an in-app WebView activity"
  grep -q "FocusGuardCheckProvider" <<<"$manifest" ||
    fail "$apk lacks Focus Guard's background check"
  awk '/E: /{p=0} /FocusGuardCheckProvider/{p=1} p && /exported/' <<<"$manifest" |
    grep -q "=true" && fail "$apk exports Focus Guard's provider"

  # R8 must keep what WorkManager creates by reflection, or every release
  # process crashes at startup (android/app/proguard-rules.pro).
  dex="$("$APKANALYZER" dex packages --defined-only "$apk")"
  for kept in 'androidx.work.impl.WorkDatabase_Impl <init>()' \
    'com.nextrep.nextrep.focusguard.FocusGuardWorker <init>(android.content.Context,androidx.work.WorkerParameters)' \
    'com.nextrep.nextrep.focusguard.FocusGuardCheckProvider <init>()'; do
    grep -qF "$kept" <<<"$dex" || fail "$apk lost $kept to shrinking"
  done
  return 0
}

verify_apk "$BUILT_APK"

echo "== Stage"
mkdir -p "$STAGING_DIR"
cp "$BUILT_APK" "$STAGING_DIR/$ARTIFACT"
(cd "$STAGING_DIR" && shasum -a 256 "$ARTIFACT" >"$ARTIFACT.sha256")

verify_apk "$STAGING_DIR/$ARTIFACT"
cmp -s "$BUILT_APK" "$STAGING_DIR/$ARTIFACT" || fail "staged copy differs from the build output"
(cd "$STAGING_DIR" && shasum -a 256 -c "$ARTIFACT.sha256")

echo "== Ready for review (not published)"
ls -l "$STAGING_DIR/$ARTIFACT"
cat "$STAGING_DIR/$ARTIFACT.sha256"
