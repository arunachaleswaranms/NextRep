import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/focus_guard/focus_guard_settings.dart';
import 'persistence_guard.dart';

/// Focus Guard's settings: the single `focus_guard_preferences` row (id 1)
/// and the `focus_guard_selected_apps` rows. No preferences row means the
/// defaults: off, nothing selected.
///
/// Persistence only, reserved for Phase 11C; the app doesn't use it yet.
final class DriftFocusGuardSettingsRepository
    implements FocusGuardSettingsRepository {
  const DriftFocusGuardSettingsRepository(this._db);

  final AppDatabase _db;

  static const _id = 1;

  @override
  Future<FocusGuardSettings> load() => guardPersistence(
    'load Focus Guard settings',
    () => _db.transaction(() async {
      final row = await (_db.select(
        _db.focusGuardPrefs,
      )..where((f) => f.id.equals(_id))).getSingleOrNull();
      final apps = await (_db.select(
        _db.focusGuardSelectedApps,
      )..orderBy([(a) => OrderingTerm.asc(a.sortOrder)])).get();
      return FocusGuardSettings(
        enabled: row?.enabled ?? false,
        dailyBudgetMinutes:
            row?.dailyBudgetMinutes ??
            FocusGuardRules.defaultDailyBudgetMinutes,
        selectedPackages: [for (final app in apps) app.packageName],
        lastNudgedOn: row?.lastNudgedOn,
      );
    }),
  );

  @override
  Future<void> save(FocusGuardSettings settings, {required DateTime at}) {
    final packages = settings.selectedPackages;
    if (!FocusGuardRules.isValidBudget(settings.dailyBudgetMinutes)) {
      throw ArgumentError.value(
        settings.dailyBudgetMinutes,
        'dailyBudgetMinutes',
      );
    }
    if (packages.length > FocusGuardRules.maxSelectedApps ||
        packages.toSet().length != packages.length ||
        !packages.every(FocusGuardRules.isValidPackage)) {
      throw ArgumentError('Invalid selected apps');
    }
    return guardPersistence(
      'save Focus Guard settings',
      () => _db.transaction(() async {
        await _db
            .into(_db.focusGuardPrefs)
            .insertOnConflictUpdate(
              FocusGuardPrefsCompanion.insert(
                id: const Value(_id),
                enabled: settings.enabled,
                dailyBudgetMinutes: settings.dailyBudgetMinutes,
                lastNudgedOn: Value(settings.lastNudgedOn),
                updatedAt: at,
              ),
            );
        // An app that stays selected keeps when it was first chosen.
        final selectedAt = {
          for (final app in await _db.select(_db.focusGuardSelectedApps).get())
            app.packageName: app.selectedAt,
        };
        await _db.delete(_db.focusGuardSelectedApps).go();
        await _db.batch(
          (batch) => batch.insertAll(_db.focusGuardSelectedApps, [
            for (final (i, packageName) in packages.indexed)
              FocusGuardSelectedAppsCompanion.insert(
                packageName: packageName,
                sortOrder: i,
                selectedAt: selectedAt[packageName] ?? at,
              ),
          ]),
        );
      }),
    );
  }
}
