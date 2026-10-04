import '../../core/time/local_date.dart';
import '../achievement/achievement.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../progress/daily_habit_progress.dart';
import '../progress/day_mode.dart';
import '../reflection/daily_reflection.dart';
import '../reminder/reminder_preferences.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/xp.dart';

/// Constants of the NextRep backup format.
///
/// The backup format is versioned on its own: [formatVersion] says how a
/// file is laid out and is unrelated to the database schema version. A
/// later app can move to format 2 without a schema change, or change the
/// schema while still writing format 1.
abstract final class BackupFormat {
  /// The `product` field of every NextRep backup.
  static const product = 'NextRep';

  /// The only format this app reads and writes.
  static const formatVersion = 1;

  /// The checksum algorithm of [formatVersion] 1.
  static const checksumAlgorithm = 'sha256';

  /// File extension, without the dot.
  static const extension = 'nextrep';

  /// Largest file accepted for restore: 16 MiB. A real backup is far
  /// smaller (an arc of 92 days with every habit tracked and a reflection
  /// each night is roughly 300 KB), so anything larger is rejected before
  /// it is read into memory.
  static const maxBytes = 16 * 1024 * 1024;

  /// A file name for a backup exported on [date]. It never contains user
  /// data.
  static String fileNameFor(LocalDate date) =>
      'nextrep-backup-${date.toIsoString()}.$extension';
}

/// A Minimum (or normal) day mode as stored.
final class BackupDayMode {
  const BackupDayMode({
    required this.date,
    required this.mode,
    required this.changedAt,
  });

  final LocalDate date;
  final DayMode mode;
  final DateTime changedAt;
}

/// A progress row as stored: the domain progress plus when it last changed.
final class BackupProgress {
  const BackupProgress({required this.progress, required this.updatedAt});

  final DailyHabitProgress progress;
  final DateTime updatedAt;
}

/// One arc with everything stored for it.
///
/// Only authoritative records are kept. Streaks, levels, Perfect Days,
/// consistency, Journey states and summaries are derived from these and are
/// recomputed after a restore, never stored in a backup.
final class BackupArc {
  const BackupArc({
    required this.session,
    required this.habits,
    this.revisions = const [],
    this.dayModes = const [],
    this.progress = const [],
    this.xp = const [],
    this.achievements = const [],
    this.reflections = const [],
  });

  final WinterArcSession session;

  /// Baseline habit configuration, as chosen in setup.
  final List<Habit> habits;

  /// Dated configuration changes.
  final List<HabitRevision> revisions;
  final List<BackupDayMode> dayModes;
  final List<BackupProgress> progress;

  /// The XP ledger. [XpAward.awardedAt] is the row's creation time.
  final List<XpAward> xp;

  /// Permanent unlocks.
  final List<AchievementUnlock> achievements;

  /// Private Journal entries. Never logged.
  final List<DailyReflection> reflections;
}

/// The reminder times. Whether reminders are on is deliberately not part
/// of a backup: after a restore both are off until the user turns them on
/// again, so restoring never starts notifications by surprise.
final class BackupReminderTimes {
  const BackupReminderTimes({required this.daily, required this.reflection});

  final ReminderTime daily;
  final ReminderTime reflection;
}

/// Everything a backup restores: every arc, and the reminder times if any
/// were ever saved.
final class BackupData {
  const BackupData({required this.arcs, this.reminders});

  static const empty = BackupData(arcs: []);

  /// Every arc, oldest first.
  final List<BackupArc> arcs;
  final BackupReminderTimes? reminders;

  bool get isEmpty => arcs.isEmpty;
}

/// A whole backup: format metadata plus the data.
final class BackupDocument {
  const BackupDocument({
    required this.exportedAt,
    required this.appVersion,
    required this.data,
  });

  final DateTime exportedAt;

  /// Version of the app that exported it, for information only.
  final String appVersion;
  final BackupData data;
}

/// Counts shown before a restore. No reflection text, ever.
final class BackupSummary {
  const BackupSummary({
    required this.arcCount,
    required this.completedArcs,
    required this.unfinishedArc,
    required this.reflectionCount,
    required this.achievementCount,
  });

  factory BackupSummary.of(BackupData data) {
    WinterArcSession? unfinished;
    var completed = 0;
    var reflections = 0;
    var achievements = 0;
    for (final arc in data.arcs) {
      if (arc.session.status == WinterArcStatus.completed) {
        completed++;
      } else {
        unfinished = arc.session;
      }
      reflections += arc.reflections.length;
      achievements += arc.achievements.length;
    }
    return BackupSummary(
      arcCount: data.arcs.length,
      completedArcs: completed,
      unfinishedArc: unfinished,
      reflectionCount: reflections,
      achievementCount: achievements,
    );
  }

  final int arcCount;
  final int completedArcs;

  /// The arc in setup or running, if any.
  final WinterArcSession? unfinishedArc;
  final int reflectionCount;
  final int achievementCount;

  bool get isEmpty => arcCount == 0;
}
