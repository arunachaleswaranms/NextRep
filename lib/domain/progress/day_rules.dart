import '../../core/time/local_date.dart';
import '../habit/habit_config.dart';
import '../xp/xp.dart';
import 'daily_habit_progress.dart';
import 'day_mode.dart';
import 'day_record.dart';

/// An XP ledger row as stored.
final class XpLedgerEntry {
  const XpLedgerEntry({
    required this.sourceKey,
    required this.reason,
    required this.amount,
    this.habitId,
  });

  final String sourceKey;
  final XpReason reason;
  final int amount;
  final String? habitId;
}

/// The persisted state of one date, read inside the transaction that will
/// change it.
final class DayContext {
  DayContext({
    required this.date,
    required this.habits,
    required this.mode,
    required Iterable<DailyHabitProgress> progress,
    required Iterable<XpLedgerEntry> ledger,
  }) : progress = {for (final p in progress) p.habitId: p},
       ledger = {for (final x in ledger) x.sourceKey: x};

  final LocalDate date;
  final HabitHistory habits;
  final DayMode mode;

  /// Every progress row stored for [date], by habit id, including rows of
  /// habits that are disabled on [date].
  final Map<String, DailyHabitProgress> progress;

  /// Ledger rows of [date] whose reason [DayRules] manages, by source key.
  final Map<String, XpLedgerEntry> ledger;

  late final DayRecord record = DayRules.recordFor(
    date: date,
    habits: habits,
    mode: mode,
    progress: progress,
  );
}

/// A requested change to the current day, before reconciliation.
final class DayChange {
  const DayChange({
    this.progress = const [],
    this.mode,
    this.revision,
    this.rename,
  });

  /// Progress rows to store.
  final List<DailyHabitProgress> progress;

  /// New mode for the day, if it changes.
  final DayMode? mode;

  /// A configuration revision effective from the day.
  final HabitRevision? revision;

  /// A new title for a habit.
  final HabitRename? rename;
}

final class HabitRename {
  const HabitRename(this.habitId, this.title);

  final String habitId;
  final String title;
}

/// XP ledger writes for one date.
final class LedgerChange {
  const LedgerChange({this.granted = const [], this.revoked = const []});

  final List<XpAward> granted;
  final List<XpLedgerEntry> revoked;

  bool get isEmpty => granted.isEmpty && revoked.isEmpty;

  bool get perfectDayGranted =>
      granted.any((a) => a.reason == XpReason.perfectDay);
  bool get perfectDayRevoked =>
      revoked.any((x) => x.reason == XpReason.perfectDay);

  /// Habit-completion XP granted for [habitId], if any.
  XpAward? habitAwardFor(String habitId) {
    for (final award in granted) {
      if (award.reason == XpReason.habitCompleted && award.habitId == habitId) {
        return award;
      }
    }
    return null;
  }
}

/// The complete, reconciled set of writes for a day, plus the resulting
/// state. Persistence applies it verbatim.
final class DaySettlement {
  const DaySettlement({
    required this.date,
    required this.progress,
    required this.ledger,
    required this.record,
    this.mode,
    this.revision,
    this.rename,
  });

  final LocalDate date;

  /// Progress rows to upsert: the requested ones plus any whose completion
  /// changed because the effective target changed.
  final List<DailyHabitProgress> progress;
  final DayMode? mode;
  final HabitRevision? revision;
  final HabitRename? rename;
  final LedgerChange ledger;

  /// The day as it will be once these writes are applied.
  final DayRecord record;

  bool get hasWrites =>
      progress.isNotEmpty ||
      mode != null ||
      revision != null ||
      rename != null ||
      !ledger.isEmpty;
}

/// Pure rules that turn a requested change to the current day into the exact
/// writes needed, keeping three invariants for the date:
///
/// 1. A habit's `completed` flag is `currentValue >= effective target`, for
///    every habit enabled that day.
/// 2. Habit XP: one `habit_completed:<habit>:<date>` award per enabled habit
///    that is completed, and none otherwise.
/// 3. Perfect Day XP: one `perfect_day:<date>` award iff the day is a normal
///    day with every enabled habit completed.
///
/// The ledger is therefore a function of the day's state. Re-settling an
/// unchanged day yields no writes, which makes every action idempotent.
abstract final class DayRules {
  /// Ledger reasons whose rows are derived from day state by these rules.
  static const managedReasons = {XpReason.habitCompleted, XpReason.perfectDay};

  /// Builds the record for [date] from stored facts.
  static DayRecord recordFor({
    required LocalDate date,
    required HabitHistory habits,
    required DayMode mode,
    required Map<String, DailyHabitProgress> progress,
  }) => DayRecord(
    date: date,
    mode: mode,
    entries: [
      for (final planned in habits.planFor(date, mode))
        HabitDayEntry(
          habit: planned.habit,
          config: planned.config,
          target: planned.target,
          progress:
              progress[planned.habit.id] ??
              DailyHabitProgress.empty(habitId: planned.habit.id, date: date),
        ),
    ],
  );

  static DaySettlement settle(
    DayContext before,
    DayChange change, {
    required DateTime now,
  }) {
    final date = before.date;
    var habits = before.habits;
    if (change.revision case final revision?) {
      habits = habits.withRevision(revision);
    }
    if (change.rename case final rename?) {
      habits = habits.withTitle(rename.habitId, rename.title);
    }
    final mode = change.mode ?? before.mode;

    final progress = {...before.progress};
    final writes = <String, DailyHabitProgress>{};
    for (final p in change.progress) {
      if (before.progress[p.habitId]?.sameStateAs(p) ?? false) continue;
      progress[p.habitId] = p;
      writes[p.habitId] = p;
    }

    // Re-evaluate completion against the (possibly new) effective targets.
    // Values are never changed here, only the completion that follows.
    for (final planned in habits.planFor(date, mode)) {
      final current = progress[planned.habit.id];
      if (current == null) continue; // no progress: cannot be complete
      final reconciled = current.withValue(
        current.currentValue,
        target: planned.target,
        now: now,
      );
      if (!reconciled.sameStateAs(current)) {
        progress[planned.habit.id] = reconciled;
        writes[planned.habit.id] = reconciled;
      }
    }

    final record = recordFor(
      date: date,
      habits: habits,
      mode: mode,
      progress: progress,
    );

    return DaySettlement(
      date: date,
      progress: writes.values.toList(growable: false),
      mode: mode == before.mode ? null : mode,
      revision: change.revision,
      rename: change.rename,
      ledger: _reconcileLedger(record, before.ledger, now),
      record: record,
    );
  }

  /// The awards [record] is worth, by source key.
  static Map<String, XpAward> expectedAwards(DayRecord record, DateTime now) {
    final date = record.date;
    return {
      for (final entry in record.entries)
        if (entry.progress.completed)
          XpRules.habitCompletionKey(entry.habit.id, date): XpAward(
            sourceKey: XpRules.habitCompletionKey(entry.habit.id, date),
            reason: XpReason.habitCompleted,
            amount: XpRules.habitCompletion,
            date: date,
            habitId: entry.habit.id,
            awardedAt: now,
          ),
      if (record.isPerfect)
        XpRules.perfectDayKey(date): XpAward(
          sourceKey: XpRules.perfectDayKey(date),
          reason: XpReason.perfectDay,
          amount: XpRules.perfectDayBonus,
          date: date,
          awardedAt: now,
        ),
    };
  }

  static LedgerChange _reconcileLedger(
    DayRecord record,
    Map<String, XpLedgerEntry> existing,
    DateTime now,
  ) {
    final expected = expectedAwards(record, now);
    return LedgerChange(
      granted: [
        for (final award in expected.values)
          if (!existing.containsKey(award.sourceKey)) award,
      ],
      revoked: [
        for (final entry in existing.values)
          if (managedReasons.contains(entry.reason) &&
              !expected.containsKey(entry.sourceKey))
            entry,
      ],
    );
  }
}
