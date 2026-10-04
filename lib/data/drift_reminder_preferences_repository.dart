import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/reminder/reminder_preferences.dart';
import 'persistence_guard.dart';

/// The single `reminder_preferences` row (id 1). No row means the defaults:
/// both reminders off.
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
      );
    },
  );

  @override
  Future<void> save(ReminderPreferences preferences, {required DateTime at}) =>
      guardPersistence('save reminder preferences', () async {
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
              ),
            );
      });
}
