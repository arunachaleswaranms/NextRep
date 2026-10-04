import '../../core/time/local_date.dart';
import 'daily_reflection.dart';

/// Persistence boundary for daily reflections. Every lookup is scoped to
/// one session.
///
/// Implementations throw `PersistenceFailure` on storage errors, without
/// any reflection text in the failure.
abstract interface class ReflectionRepository {
  /// Every reflection of [sessionId], newest date first.
  Future<List<DailyReflection>> reflectionsFor(int sessionId);

  /// The reflection of [sessionId] for [date], or null.
  Future<DailyReflection?> reflectionOn(int sessionId, LocalDate date);

  /// The date and mood of every reflection of [sessionId], oldest first.
  /// No text is read, so insights never handle what the user wrote.
  Future<List<MoodMark>> moodsFor(int sessionId);

  /// Number of reflections of [sessionId].
  Future<int> countFor(int sessionId);

  /// Stores [content] as the reflection of [sessionId] on [date], replacing
  /// the existing one if there is one (its creation time is kept).
  Future<DailyReflection> save({
    required int sessionId,
    required LocalDate date,
    required ReflectionContent content,
    required DateTime at,
  });
}
