import '../../core/time/local_date.dart';
import 'launchable_apps.dart';

/// Limits of Focus Guard's stored configuration.
abstract final class FocusGuardRules {
  /// The daily budget, in minutes, across every selected app.
  static const minDailyBudgetMinutes = 1;
  static const maxDailyBudgetMinutes = 24 * 60;

  /// The budget before the user picks one.
  static const defaultDailyBudgetMinutes = 60;

  /// Most apps one Focus Guard can watch.
  static const maxSelectedApps = 100;

  /// Longest package name accepted (Android allows far fewer in practice).
  static const maxPackageNameLength = 255;

  static bool isValidBudget(int minutes) =>
      minutes >= minDailyBudgetMinutes && minutes <= maxDailyBudgetMinutes;

  static bool isValidPackage(String packageName) =>
      packageName.length <= maxPackageNameLength &&
      LaunchableApps.isPackageName(packageName);
}

/// Focus Guard's persisted configuration (schema v6).
///
/// Reserved for Phase 11C, which adds the feature itself. Only what the
/// user chose is kept, plus the date of the day's single nudge: never any
/// amount of app usage, today's or historical.
final class FocusGuardSettings {
  const FocusGuardSettings({
    required this.enabled,
    required this.dailyBudgetMinutes,
    required this.selectedPackages,
    this.lastNudgedOn,
  });

  /// Off, nothing selected, the default budget.
  static const defaults = FocusGuardSettings(
    enabled: false,
    dailyBudgetMinutes: FocusGuardRules.defaultDailyBudgetMinutes,
    selectedPackages: [],
  );

  final bool enabled;
  final int dailyBudgetMinutes;

  /// Package names, in the user's order, without duplicates.
  final List<String> selectedPackages;

  /// The local date Focus Guard last nudged on, if ever.
  final LocalDate? lastNudgedOn;
}

/// Persistence boundary for [FocusGuardSettings].
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class FocusGuardSettingsRepository {
  /// The stored settings, or [FocusGuardSettings.defaults] if none were
  /// ever saved.
  Future<FocusGuardSettings> load();

  /// Replaces the stored settings. Throws [ArgumentError] for a budget or
  /// package list outside [FocusGuardRules], writing nothing.
  Future<void> save(FocusGuardSettings settings, {required DateTime at});
}
