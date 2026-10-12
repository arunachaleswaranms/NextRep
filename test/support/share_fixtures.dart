import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/share_gateway.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/day_summary.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'builders.dart';

/// Last night's bedtime logged in [shareSummary] for Sleep Before Target:
/// a time that must never appear on a card.
final loggedBedtime = NightTime(22, 47);

/// A private reflection-like string that must never reach a card.
const privateNote = 'PRIVATE-JOURNAL-TEXT';

/// The eight templates of v1.0, in catalogue order.
final v1Templates = [
  for (final id in const [
    'workout',
    'water',
    'learning',
    'english',
    'no_junk_food',
    'sleep_before',
    'meditation',
    'journal',
  ])
    HabitTemplateCatalog.byId(id)!,
];

/// [templates] (default: [v1Templates]) plus custom habits up to [count]
/// (at most 12), in display order. Custom ones get [customTitle] if given.
List<Habit> catalogHabits({
  int count = 8,
  String? customTitle,
  List<HabitTemplate>? templates,
}) {
  final created = DateTime(2026, 10, 1);
  final bundled = (templates ?? v1Templates).take(count).toList();
  return [
    for (final (i, template) in bundled.indexed)
      template.toHabit(sortOrder: i, createdAt: created, enabled: true),
    for (var i = bundled.length; i < count; i++)
      Habit(
        id: 'custom_$i',
        title: customTitle ?? 'Custom habit $i',
        type: i.isEven ? HabitType.binary : HabitType.duration,
        target: i.isEven ? 1 : 15,
        minimumTarget: i.isEven ? 1 : 5,
        unit: i.isEven ? null : 'min',
        iconKey: 'star',
        enabled: true,
        sortOrder: i,
        createdAt: created,
      ),
  ];
}

/// Today's summary on challenge day [today] of an arc with [habits].
///
/// [done] habits are complete today at their effective target (Sleep
/// Before Target at [loggedBedtime]); [streakDays] earlier days had every
/// habit complete. [session] defaults to a rolling arc from [day1].
DaySummary shareSummary({
  required List<Habit> habits,
  int today = 24,
  Set<String> done = const {},
  int streakDays = 0,
  DayMode mode = DayMode.normal,
  int xp = 0,
  WinterArcSession? session,
  List<HabitRevision> revisions = const [],
}) {
  final arc = session ?? activeSession();
  final date = arc.startDate.addDays(today - 1);
  final history = HabitHistory(habits: habits, revisions: revisions);
  DailyHabitProgress complete(Habit habit, LocalDate on, DayMode dayMode) {
    final target = history.configOn(habit, on).targetFor(dayMode);
    final value = habit.type.isClockTime ? loggedBedtime.value : target;
    return progress(habit.id, on, value, completed: true);
  }

  return DaySummary.fromHistory(
    ArcHistory(
      session: arc,
      today: date,
      records: ArcRecords(
        habits: history,
        progress: [
          for (var d = 1; d <= streakDays; d++)
            for (final habit in habits)
              complete(habit, date.addDays(-d), DayMode.normal),
          for (final habit in habits)
            if (done.contains(habit.id)) complete(habit, date, mode),
        ],
        modes: {if (mode == DayMode.minimum) date: mode},
        xpByDate: {date: xp},
        totalXp: xp,
      ),
    ),
  );
}

/// A Seasonal Winter Arc for [year], joined on challenge day [joinDay].
WinterArcSession seasonalSession({int year = 2026, int joinDay = 1}) {
  final start = LocalDate(year, 10, 1);
  return WinterArcSession(
    id: 2,
    kind: ArcKind.seasonalWinter,
    startDate: start,
    endDate: LocalDate(year, 12, 31),
    participationStartDate: start.addDays(joinDay - 1),
    status: WinterArcStatus.active,
    createdAt: DateTime(year, 10, 1),
    startedAt: DateTime(year, 10, 1),
  );
}

/// Records share requests instead of opening the system share sheet.
final class FakeShareGateway implements ShareGateway {
  FakeShareGateway({this.outcome = ShareOutcome.shared});

  ShareOutcome outcome;

  /// Makes the next request throw, like a platform failure.
  Object? error;

  /// While set, a request waits for it (the sheet is "open").
  Completer<void>? hold;

  final requests = <({ShareFile file, String text, Rect? origin})>[];

  ShareFile get lastFile => requests.last.file;

  @override
  Future<ShareOutcome> share(
    ShareFile file, {
    required String text,
    Rect? origin,
  }) async {
    requests.add((file: file, text: text, origin: origin));
    if (hold case final hold?) await hold.future;
    if (error case final error?) throw error;
    return outcome;
  }
}

/// The width and height in a PNG's IHDR header, or null if [bytes] is not
/// a PNG.
({int width, int height})? pngSize(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}
