import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/feedback/feedback_preferences.dart';
import 'persistence_guard.dart';

/// The single `feedback_preferences` row (id 1, schema v7). No row means
/// the defaults ([FeedbackPreferences.defaults]); reading never inserts
/// one.
///
/// Read by Sound & Feedback and, on every completion, by the sound engine
/// (Phase 12G); written only by Sound & Feedback and by a format-4 restore.
final class DriftFeedbackPreferencesRepository
    implements FeedbackPreferencesRepository {
  const DriftFeedbackPreferencesRepository(this._db);

  final AppDatabase _db;

  static const _id = 1;

  @override
  Future<FeedbackPreferences> load() =>
      guardPersistence('load feedback preferences', () async {
        final row = await (_db.select(
          _db.feedbackPrefs,
        )..where((f) => f.id.equals(_id))).getSingleOrNull();
        if (row == null) return FeedbackPreferences.defaults;
        return FeedbackPreferences(
          soundsEnabled: row.soundsEnabled,
          soundTheme: row.soundTheme,
        );
      });

  @override
  Future<void> save(FeedbackPreferences preferences, {required DateTime at}) =>
      guardPersistence('save feedback preferences', () async {
        await _db
            .into(_db.feedbackPrefs)
            .insertOnConflictUpdate(
              FeedbackPrefsCompanion.insert(
                id: const Value(_id),
                soundsEnabled: preferences.soundsEnabled,
                soundTheme: preferences.soundTheme,
                updatedAt: at,
              ),
            );
      });
}
