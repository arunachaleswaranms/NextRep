import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/reminder/reminder_preferences.dart';
import 'persistence_guard.dart';

/// The single `reminder_preferences` row (id 1). No row means the defaults:
/// every reminder off.
final class DriftReminderPreferencesRepository
    implements ReminderPreferencesRepository {
  const DriftReminderPreferencesRepository(this._db);

  final AppDatabase _db;

  static const _id = 1;

  @override
  Future<ReminderPreferences> load() => guardPersistence(
    'load reminder preferences',
    () async {
      final row = await (_db.select(
        _db.reminderPrefs,
      )..where((r) => r.id.equals(_id))).getSingleOrNull();
      if (row == null) return ReminderPreferences.defaults;
      return ReminderPreferences(
        dailyEnabled: row.dailyEnabled,
        dailyTime: ReminderTime(row.dailyHour, row.dailyMinute),
        reflectionEnabled: row.reflectionEnabled,
        reflectionTime: ReminderTime(row.reflectionHour, row.reflectionMinute),
        hydrationEnabled: row.hydrationEnabled,
        // The table's CHECK only admits valid windows.
        hydrationWindow: HydrationWindow(
          ReminderTime(row.hydrationStartHour, row.hydrationStartMinute),
          ReminderTime(row.hydrationEndHour, row.hydrationEndMinute),
        ),
        hydrationMode: row.hydrationMode,
      );
    },
  );

  @override
  Future<void> save(ReminderPreferences preferences, {required DateTime at}) =>
      guardPersistence('save reminder preferences', () async {
        final window = preferences.hydrationWindow;
        await _db
            .into(_db.reminderPrefs)
            .insertOnConflictUpdate(
              ReminderPrefsCompanion.insert(
                id: const Value(_id),
                dailyEnabled: preferences.dailyEnabled,
                dailyHour: preferences.dailyTime.hour,
                dailyMinute: preferences.dailyTime.minute,
                reflectionEnabled: preferences.reflectionEnabled,
                reflectionHour: preferences.reflectionTime.hour,
                reflectionMinute: preferences.reflectionTime.minute,
                updatedAt: at,
                hydrationEnabled: Value(preferences.hydrationEnabled),
                hydrationStartHour: Value(window.start.hour),
                hydrationStartMinute: Value(window.start.minute),
                hydrationEndHour: Value(window.end.hour),
                hydrationEndMinute: Value(window.end.minute),
                hydrationMode: Value(preferences.hydrationMode),
              ),
            );
      });
}
