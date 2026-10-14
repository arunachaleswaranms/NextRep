import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../reminder/reminder_scheduler.dart';
import 'focus_guard_background.dart';
import 'focus_guard_platform.dart';
import 'focus_guard_settings.dart';
import 'launchable_apps.dart';
import 'today_usage.dart';

/// NextRep's Android package, which the app picker leaves out.
const nextRepPackage = 'com.nextrep.nextrep';

/// The payload of a tap on Focus Guard's nudge. It opens Today, like the
/// reminders (`AppRoutes.forReminder`). Not a reminder kind: the nudge is
/// posted by the native background check, never by the reminder planner.
const focusGuardTapPayload = 'focus_guard';

/// Focus Guard as it stands right now: the stored settings and the two
/// separate permissions, both read afresh.
final class FocusGuardStatus {
  const FocusGuardStatus({
    required this.settings,
    required this.access,
    required this.nudgesAllowed,
  });

  final FocusGuardSettings settings;

  /// Usage Access: lets Focus Guard measure.
  final UsageAccess access;

  /// Notifications: let Focus Guard nudge. Independent of [access].
  final bool nudgesAllowed;

  /// False where the platform has no Usage Access (iOS): Focus Guard is
  /// omitted there.
  bool get supported => access != UsageAccess.unsupported;

  bool get hasApps => settings.selectedPackages.isNotEmpty;

  /// What turning Focus Guard on needs first.
  bool get canEnable => access == UsageAccess.granted && hasApps;

  /// Whether the background check is meant to run.
  bool get monitoring => FocusGuardBackground.shouldRun(
    enabled: settings.enabled,
    access: access,
    selectedApps: settings.selectedPackages.length,
    dailyBudgetMinutes: settings.dailyBudgetMinutes,
  );
}

/// What the Today card shows.
final class FocusGuardToday {
  const FocusGuardToday({required this.status, this.usage});

  final FocusGuardStatus status;

  /// Today's usage, read only while Focus Guard is on with apps selected.
  final TodayUsage? usage;
}

/// The result of turning Focus Guard on or off.
enum FocusGuardToggle {
  /// On, and its nudge can appear.
  on,

  /// On and measuring, but notifications are off, so no nudge can appear.
  onWithoutNudges,

  off,

  /// Not turned on: Usage Access isn't granted.
  needsUsageAccess,

  /// Not turned on: no app is selected.
  needsApps,

  /// Not turned on: this platform has no Focus Guard.
  unsupported,
}

/// Focus Guard's use cases: settings, today's usage, and keeping the
/// background check in line with them.
///
/// Settings are application-level, not owned by any Arc. Only an explicit
/// [setEnabled] call (a user's tap) ever turns Focus Guard on, and it is
/// the only moment notification permission may be asked for. Nothing here
/// opens system settings except [openUsageAccessSettings], and nothing here
/// stores an amount of usage. Writes and reconciliation run one at a time.
final class FocusGuardService {
  FocusGuardService({
    required this._settings,
    required this._platform,
    required this._background,
    required this._notifications,
    required this._clock,
  });

  final FocusGuardSettingsRepository _settings;
  final FocusGuardPlatform _platform;
  final FocusGuardBackgroundScheduler _background;
  final ReminderScheduler _notifications;
  final Clock _clock;
  final _queue = SerialQueue();

  /// Settings plus both permissions, read now (never cached: Android
  /// doesn't restart the app when the user changes them).
  Future<FocusGuardStatus> status() async {
    final settings = await _settings.load();
    final access = await _access();
    return FocusGuardStatus(
      settings: settings,
      access: access,
      nudgesAllowed: access == UsageAccess.unsupported
          ? false
          : await _nudges(),
    );
  }

  /// The Today card's state. Usage is measured from local midnight to now
  /// on every call; when it can't be, it is [UsageUnavailable], never an
  /// older value or zero.
  Future<FocusGuardToday> today() async {
    final status = await this.status();
    if (!status.supported || !status.settings.enabled || !status.hasApps) {
      return FocusGuardToday(status: status);
    }
    final usage = await TodayUsageReader(
      platform: _platform,
      clock: _clock,
    ).read(status.settings.selectedPackages.toSet());
    return FocusGuardToday(status: status, usage: usage);
  }

  /// Apps the user can pick: launcher apps only, one per package, NextRep
  /// left out, sorted by label. Labels are read live and never stored.
  Future<List<LaunchableAppCandidate>> pickableApps() async =>
      LaunchableApps.forPicker(
        await _platform.launchableApps(),
        ownPackage: nextRepPackage,
      );

  /// Opens the system Usage Access page. Only for the user's tap.
  Future<void> openUsageAccessSettings() => _platform.openUsageAccessSettings();

  /// Turns Focus Guard on or off.
  ///
  /// On needs Usage Access and at least one app; otherwise nothing is
  /// saved and the result says what is missing. Notification permission is
  /// asked for if it isn't granted, but Focus Guard turns on either way:
  /// it still measures, it just can't nudge. Off keeps the apps, the budget
  /// and the day's nudge record, so turning it back on the same day never
  /// nudges twice.
  Future<FocusGuardToggle> setEnabled(bool enabled) => _queue.run(() async {
    final settings = await _settings.load();
    if (!enabled) {
      if (settings.enabled) {
        await _settings.save(
          settings.copyWith(enabled: false),
          at: _clock.now(),
        );
      }
      await _reconcile();
      return FocusGuardToggle.off;
    }
    final access = await _access();
    if (access == UsageAccess.unsupported) return FocusGuardToggle.unsupported;
    if (access != UsageAccess.granted) return FocusGuardToggle.needsUsageAccess;
    if (settings.selectedPackages.isEmpty) return FocusGuardToggle.needsApps;

    var nudges = await _nudges();
    if (!nudges && !await _permissionGranted()) {
      await _requestPermission();
      nudges = await _nudges();
    }
    await _settings.save(settings.copyWith(enabled: true), at: _clock.now());
    await _reconcile();
    return nudges ? FocusGuardToggle.on : FocusGuardToggle.onWithoutNudges;
  });

  /// Sets the combined daily budget. Throws a [DomainFailure] outside
  /// 1–1440 minutes, saving nothing.
  Future<void> setDailyBudget(int minutes) => _queue.run(() async {
    if (!FocusGuardRules.isValidBudget(minutes)) {
      throw DomainFailure(
        DomainRule.invalidFocusGuardBudget,
        'Budget out of range',
      );
    }
    final settings = await _settings.load();
    if (settings.dailyBudgetMinutes == minutes) return;
    await _settings.save(
      settings.copyWith(dailyBudgetMinutes: minutes),
      at: _clock.now(),
    );
    await _reconcile();
  });

  /// Replaces the selected apps, in order, without duplicates. Throws a
  /// [DomainFailure] for more than [FocusGuardRules.maxSelectedApps] or a
  /// malformed package name, saving nothing. An empty selection is allowed;
  /// Focus Guard then measures nothing and the background check stops.
  Future<void> setSelectedApps(List<String> packages) => _queue.run(() async {
    final unique = <String>[];
    for (final name in packages) {
      if (!unique.contains(name)) unique.add(name);
    }
    if (unique.length > FocusGuardRules.maxSelectedApps ||
        !unique.every(FocusGuardRules.isValidPackage)) {
      throw DomainFailure(
        DomainRule.invalidFocusGuardApps,
        'Invalid app selection',
      );
    }
    final settings = await _settings.load();
    await _settings.save(
      settings.copyWith(selectedPackages: unique),
      at: _clock.now(),
    );
    await _reconcile();
  });

  /// Schedules or cancels the background check to match the stored
  /// settings and Usage Access now. Safe at launch, on resume and after a
  /// restore; never prompts or opens settings. Returns whether it runs.
  Future<bool> reconcile() => _queue.run(_reconcile);

  Future<bool> _reconcile() async {
    final settings = await _settings.load();
    return FocusGuardBackground.reconcile(
      _background,
      enabled: settings.enabled,
      access: await _access(),
      selectedApps: settings.selectedPackages.length,
      dailyBudgetMinutes: settings.dailyBudgetMinutes,
    );
  }

  /// A failing access check counts as no access.
  Future<UsageAccess> _access() async {
    try {
      return await _platform.usageAccess();
    } catch (_) {
      return UsageAccess.notGranted;
    }
  }

  /// A failing check counts as "can't nudge".
  Future<bool> _nudges() async {
    try {
      return await _platform.nudgesAllowed();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _permissionGranted() async {
    try {
      return await _notifications.permissionGranted();
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _notifications.requestPermission();
    } catch (_) {
      // Focus Guard still turns on; it just can't nudge.
    }
  }
}
