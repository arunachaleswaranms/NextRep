import '../../core/time/local_date.dart';

/// XP amounts. Never use XP literals outside this class.
abstract final class XpRules {
  /// Awarded once per habit per challenge day when the habit is completed.
  static const int habitCompletion = 15;

  /// Idempotency key for the habit-completion award.
  ///
  /// The ledger holds at most one transaction per key per session, so the
  /// same habit-day can never be credited twice.
  static String habitCompletionKey(String habitId, LocalDate date) =>
      'habit_completed:$habitId:${date.toIsoString()}';
}

/// Why XP was awarded. Persisted by [name].
enum XpReason { habitCompleted }

/// A single XP ledger entry.
final class XpAward {
  const XpAward({
    required this.sourceKey,
    required this.reason,
    required this.amount,
    required this.date,
    required this.awardedAt,
    this.habitId,
  });

  final String sourceKey;
  final XpReason reason;
  final int amount;
  final LocalDate date;
  final DateTime awardedAt;
  final String? habitId;
}
