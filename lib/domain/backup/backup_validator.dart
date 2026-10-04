import 'package:characters/characters.dart';

import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../habit/habit_edit.dart';
import '../habit/setup_habit_rules.dart';
import '../progress/day_mode.dart';
import '../reflection/daily_reflection.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/xp.dart';
import 'backup_document.dart';

/// A backup that passed every check in [BackupValidator]. Only the
/// validator can create one, and a restore only accepts one, so nothing
/// unvalidated can ever reach the database.
final class ValidatedBackup {
  ValidatedBackup._(this.document) : summary = BackupSummary.of(document.data);

  final BackupDocument document;
  final BackupSummary summary;

  BackupData get data => document.data;
}

/// Checks the rules that span records, before anything is written.
///
/// A decoded document already has the right shape and types (see
/// `BackupCodec`). This adds the invariants the app relies on:
///
/// * at most one unfinished (setup or active) arc; unique arc ids; every
///   arc keeps the invariants of its kind (`WinterArcRules.problemWith`: a
///   rolling 92-day window joined on its start date, or one year's 1
///   October – 31 December season joined inside it; no participation
///   while in setup); a completed arc is over and a started one has
///   started
/// * habits: unique id and sort order per arc, at most
///   [SetupHabitRules.maxHabits], a known type, a target within the
///   editing limits (a clock-time target in the night window, the same on
///   Minimum Days), a title like one the app could have saved
/// * every revision, progress row, XP entry, day mode, unlock and
///   reflection references its arc (the format nests them) and, where it
///   has one, a habit of that arc; its date is a participating date of the
///   arc (never before the user joined) and not after the export
/// * a clock-time habit's progress is "not logged" (0) or a night time, and
///   its completion agrees with the target in effect on that date (with
///   that date's revisions and mode, never today's)
/// * uniqueness: one progress row per habit and date, one revision per
///   habit and date, one mode / reflection per date, one unlock per key,
///   one XP entry per source key
/// * XP source keys are the idempotency keys the app derives
///   (`habit_completed:<habit>:<date>`, `perfect_day:<date>`)
/// * reflections follow the Journal's rules (trimmed, not empty, at most
///   240 characters per answer)
/// * an arc still in setup has no history yet
///
/// Error messages carry positions (`arcs[1].progress[4]`) and rule names
/// only, never values from the file.
abstract final class BackupValidator {
  /// Most arcs a backup may hold; far more than a lifetime of 92-day arcs.
  static const maxArcs = 1000;

  static ValidatedBackup validate(BackupDocument document) {
    final data = document.data;
    if (data.arcs.length > maxArcs) _fail(r'$.data.arcs', 'too many arcs');
    // Nothing can be dated after the exporting device's local date. That
    // date is at most one day ahead of the UTC date of the export in any
    // time zone, so this holds wherever the backup was made.
    final latest = LocalDate.fromDateTime(document.exportedAt.toUtc())
        .addDays(1);

    final ids = <int>{};
    var unfinished = 0;
    for (final (i, arc) in data.arcs.indexed) {
      final at = 'arcs[$i]';
      if (!ids.add(arc.session.id)) _fail(at, 'duplicate arc id');
      if (arc.session.status != WinterArcStatus.completed) unfinished++;
      if (unfinished > 1) _fail(at, 'more than one unfinished arc');
      _checkArc(arc, at, latest);
    }
    return ValidatedBackup._(document);
  }

  static void _checkArc(BackupArc arc, String at, LocalDate latest) {
    final session = arc.session;
    // Fixed wording from the rules; it never contains file values.
    if (WinterArcRules.problemWith(session) case final problem?) {
      _fail(at, problem);
    }
    final joined = session.participationStartDate;
    if (joined != null && joined.isAfter(latest)) {
      _fail('$at.participationStartDate', 'after the export date');
    }
    // A rolling arc's provisional start is the day its setup was made; a
    // seasonal setup made in September starts on a later 1 October.
    if (session.kind == ArcKind.rolling92 &&
        session.startDate.isAfter(latest)) {
      _fail('$at.startDate', 'after the export date');
    }
    if (session.status == WinterArcStatus.completed &&
        !session.endDate.isBefore(latest)) {
      _fail('$at.endDate', 'a completed arc that has not ended');
    }

    // History only exists on participating dates: never before the user
    // joined a seasonal arc.
    bool inArc(LocalDate date) => session.isParticipatingOn(date);
    void checkDate(LocalDate date, String where) {
      if (!inArc(date)) _fail(where, 'date outside the arc');
      if (date.isAfter(latest)) _fail(where, 'date after the export');
    }

    // Habits.
    if (arc.habits.isEmpty) _fail('$at.habits', 'an arc has habits');
    if (arc.habits.length > SetupHabitRules.maxHabits) {
      _fail('$at.habits', 'too many habits');
    }
    final habits = <String, Habit>{};
    final sortOrders = <int>{};
    for (final (j, habit) in arc.habits.indexed) {
      final where = '$at.habits[$j]';
      if (habits.containsKey(habit.id)) _fail(where, 'duplicate habit id');
      habits[habit.id] = habit;
      if (!sortOrders.add(habit.sortOrder)) {
        _fail(where, 'duplicate sort order');
      }
      final title = habit.title.trim();
      if (title.isEmpty ||
          title != habit.title ||
          title.length > HabitEditRules.maxTitleLength) {
        _fail('$where.title', 'not a valid habit name');
      }
      if (!HabitEditRules.isValidConfig(habit.type, habit.baseline)) {
        _fail('$where.target', 'target not valid for the habit');
      }
    }

    final hasHistory =
        arc.revisions.isNotEmpty ||
        arc.dayModes.isNotEmpty ||
        arc.progress.isNotEmpty ||
        arc.xp.isNotEmpty ||
        arc.achievements.isNotEmpty ||
        arc.reflections.isNotEmpty;
    if (session.status == WinterArcStatus.setup && hasHistory) {
      _fail(at, 'an arc in setup has no history');
    }

    Habit habitFor(String id, String where) =>
        habits[id] ?? _fail(where, 'unknown habit');

    final revisionKeys = <(String, LocalDate)>{};
    for (final (j, revision) in arc.revisions.indexed) {
      final where = '$at.habitRevisions[$j]';
      final habit = habitFor(revision.habitId, where);
      // Revisions take effect on the next challenge day, which can be the
      // day after the export.
      if (!inArc(revision.effectiveFrom) ||
          revision.effectiveFrom.isAfter(latest.addDays(1))) {
        _fail('$where.effectiveFrom', 'date outside the arc');
      }
      if (!revisionKeys.add((revision.habitId, revision.effectiveFrom))) {
        _fail(where, 'duplicate revision');
      }
      if (!HabitEditRules.isValidConfig(habit.type, revision.config)) {
        _fail('$where.target', 'target not valid for the habit');
      }
    }

    final modeDates = <LocalDate>{};
    for (final (j, mode) in arc.dayModes.indexed) {
      final where = '$at.dayModes[$j]';
      checkDate(mode.date, '$where.date');
      if (!modeDates.add(mode.date)) _fail(where, 'duplicate day mode');
    }

    final history = HabitHistory(habits: arc.habits, revisions: arc.revisions);
    final modes = {for (final m in arc.dayModes) m.date: m.mode};
    final progressKeys = <(String, LocalDate)>{};
    for (final (j, row) in arc.progress.indexed) {
      final where = '$at.progress[$j]';
      final p = row.progress;
      final habit = habitFor(p.habitId, where);
      checkDate(p.date, '$where.date');
      if (!progressKeys.add((p.habitId, p.date))) {
        _fail(where, 'duplicate progress');
      }
      if (habit.type.isClockTime) {
        if (p.currentValue != 0 && !NightTime.isValidValue(p.currentValue)) {
          _fail('$where.value', 'not a clock time');
        }
        // The target of that date, with its revisions and mode.
        final target = history
            .configOn(habit, p.date)
            .targetFor(modes[p.date] ?? DayMode.normal);
        if (p.completed != habit.type.isCompletedBy(p.currentValue, target)) {
          _fail('$where.completed', 'does not match the recorded time');
        }
      }
    }

    final sourceKeys = <String>{};
    for (final (j, x) in arc.xp.indexed) {
      final where = '$at.xp[$j]';
      checkDate(x.date, '$where.date');
      if (!sourceKeys.add(x.sourceKey)) _fail(where, 'duplicate source key');
      final expectedKey = switch (x.reason) {
        XpReason.habitCompleted => XpRules.habitCompletionKey(
          habitFor(x.habitId ?? _fail(where, 'missing habit'), where).id,
          x.date,
        ),
        XpReason.perfectDay =>
          x.habitId == null
              ? XpRules.perfectDayKey(x.date)
              : _fail(where, 'a Perfect Day bonus has no habit'),
      };
      if (x.sourceKey != expectedKey) {
        _fail('$where.sourceKey', 'does not match the entry');
      }
    }

    final unlocked = <Object>{};
    for (final (j, unlock) in arc.achievements.indexed) {
      final where = '$at.achievements[$j]';
      checkDate(unlock.unlockedOn, '$where.earnedOn');
      if (!unlocked.add(unlock.key)) _fail(where, 'duplicate achievement');
    }

    final reflectionDates = <LocalDate>{};
    for (final (j, reflection) in arc.reflections.indexed) {
      final where = '$at.reflections[$j]';
      checkDate(reflection.date, '$where.date');
      if (!reflectionDates.add(reflection.date)) {
        _fail(where, 'duplicate reflection');
      }
      _checkReflection(reflection, where);
    }
  }

  /// The Journal's own rules: what `ReflectionRules.validate` would have
  /// produced from what the user typed.
  static void _checkReflection(DailyReflection r, String where) {
    for (final (name, text) in [
      ('win', r.win),
      ('improvement', r.improvement),
    ]) {
      if (text == null) continue;
      if (text.trim() != text || text.isEmpty) {
        _fail('$where.$name', 'not trimmed');
      }
      if (text.characters.length > ReflectionRules.maxTextLength) {
        _fail('$where.$name', 'over the length limit');
      }
    }
    if (r.mood == null && r.win == null && r.improvement == null) {
      _fail(where, 'an empty reflection');
    }
  }

  static Never _fail(String where, String problem) =>
      throw BackupFailure(BackupProblem.invalidData, '$where: $problem');
}
