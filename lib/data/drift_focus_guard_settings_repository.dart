import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/focus_guard/focus_guard_settings.dart';
import 'persistence_guard.dart';

/// Focus Guard's settings: the single `focus_guard_preferences` row (id 1)
/// and the `focus_guard_selected_apps` rows. No preferences row means the
/// defaults: off, nothing selected.
///
/// The same rows are read by the native background check, which also
/// claims `last_nudged_on` when it nudges (`FocusGuardStore.kt`). So [save]
/// never overwrites a stored `last_nudged_on`: settings loaded before the
/// worker nudged and saved afterwards keep the worker's date.
///
/// Package names are private configuration, so storage errors keep no
/// details that could quote them ([guardPrivatePersistence]).
final class DriftFocusGuardSettingsRepository
    implements FocusGuardSettingsRepository {
  const DriftFocusGuardSettingsRepository(this._db);

  final AppDatabase _db;

  static const _id = 1;

  @override
  Future<FocusGuardSettings> load() => guardPrivatePersistence(
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
    return guardPrivatePersistence(
      'save Focus Guard settings',
      () => _db.transaction(() async {
        // One upsert: an existing row keeps its last_nudged_on, whatever
        // [settings] holds (it may predate the worker's nudge). Only a new
        // row takes it, as there is no stored date to keep then.
        await _db
            .into(_db.focusGuardPrefs)
            .insert(
              FocusGuardPrefsCompanion.insert(
                id: const Value(_id),
                enabled: settings.enabled,
                dailyBudgetMinutes: settings.dailyBudgetMinutes,
                lastNudgedOn: Value(settings.lastNudgedOn),
                updatedAt: at,
              ),
              onConflict: DoUpdate(
                (_) => FocusGuardPrefsCompanion(
                  enabled: Value(settings.enabled),
                  dailyBudgetMinutes: Value(settings.dailyBudgetMinutes),
                  updatedAt: Value(at),
                ),
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
