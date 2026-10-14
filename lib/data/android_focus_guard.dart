import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/focus_guard/focus_guard_background.dart';
import '../domain/focus_guard/focus_guard_platform.dart';
import 'focus_guard_codec.dart';

/// The Android side of Focus Guard (`FocusGuardChannel.kt`). Created only on
/// Android; elsewhere the app uses [UnsupportedFocusGuardPlatform].
const _channel = MethodChannel('com.nextrep.nextrep/focus_guard');

/// [FocusGuardPlatform] over the native channel: Usage Access through
/// AppOpsManager, launcher apps through LauncherApps, and foreground time
/// from UsageStats events, all read live. Results are decoded fail-closed
/// by [FocusGuardCodec]. Nothing is stored on either side.
final class AndroidFocusGuardPlatform implements FocusGuardPlatform {
  const AndroidFocusGuardPlatform();

  @override
  Future<UsageAccess> usageAccess() async => FocusGuardCodec.usageAccess(
    await _channel.invokeMethod<Object?>('usageAccess'),
  );

  @override
  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod<Object?>('openUsageAccessSettings');

  @override
  Future<bool> nudgesAllowed() async =>
      await _channel.invokeMethod<Object?>('nudgesAllowed') == true;

  @override
  Future<List<LaunchableAppCandidate>> launchableApps() async =>
      FocusGuardCodec.launchableApps(
        await _channel.invokeMethod<Object?>('launchableApps'),
      );

  @override
  Future<Map<String, Duration>> foregroundTime(
    Set<String> packages, {
    required DateTime from,
    required DateTime to,
  }) async => FocusGuardCodec.foregroundTime(
    await _channel.invokeMethod<Object?>('foregroundTime', {
      'packages': packages.toList(),
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    }),
    packages,
  );
}

/// The one unique periodic WorkManager job (`FocusGuardScheduler.kt`):
/// `KEEP`, so repeated calls never add a job or move its timing.
final class AndroidFocusGuardBackgroundScheduler
    implements FocusGuardBackgroundScheduler {
  const AndroidFocusGuardBackgroundScheduler();

  @override
  Future<void> ensureScheduled() =>
      _channel.invokeMethod<Object?>('ensureScheduled');

  @override
  Future<void> cancel() => _channel.invokeMethod<Object?>('cancelSchedule');
}

/// Taps on Focus Guard's native nudge. [takeLaunchTap] answers whether the
/// app was opened by one (once); [taps] reports those made while it runs.
final class AndroidFocusGuardTaps {
  AndroidFocusGuardTaps() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nudgeTapped') _taps.add(null);
    });
  }

  final _taps = StreamController<void>.broadcast();

  Stream<void> get taps => _taps.stream;

  Future<bool> takeLaunchTap() async =>
      await _channel.invokeMethod<Object?>('takeLaunchNudgeTap') == true;
}
