import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reminder/hydration_planner.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/builders.dart';

const _t = ReminderTime.new;

/// The built-in Water habit as a starter arc has it: 8 glasses, 3 on a
/// Minimum Day.
final _water = habit('water', target: 8, minimum: 3);

ArcRecords _records({
  List<Habit>? habits,
  List<HabitRevision> revisions = const [],
  List<DailyHabitProgress> progress = const [],
  Map<LocalDate, DayMode> modes = const {},
}) => ArcRecords(
  habits: HabitHistory(habits: habits ?? [_water], revisions: revisions),
  progress: progress,
  modes: modes,
  xpByDate: const {},
  totalXp: 0,
);

/// The seven hydration days from [now]'s date, as the reminder service
/// gathers them.
List<HydrationDay> _days(
  ArcRecords records,
  DateTime now, {
  WinterArcSession? arc,
  DateTime? loggedAt,
}) {
  final today = LocalDate.fromDateTime(now);
  return [
    for (var offset = 0; offset < HydrationPlanner.horizonDays; offset++)
      HydrationDay.of(
        arc: arc ?? activeSession(),
        records: records,
        date: today.addDays(offset),
        lastLoggedAt: offset == 0 ? loggedAt : null,
      ),
  ];
}

ReminderPreferences _prefs({
  bool daily = false,
  bool reflection = false,
  bool hydration = true,
  HydrationMode mode = HydrationMode.balanced,
  HydrationWindow window = HydrationWindow.defaults,
}) => ReminderPreferences(
  dailyEnabled: daily,
  dailyTime: const ReminderTime(8, 0),
  reflectionEnabled: reflection,
  reflectionTime: const ReminderTime(21, 0),
  hydrationEnabled: hydration,
  hydrationMode: mode,
  hydrationWindow: window,
);

/// Hydration reminders planned at [now].
List<PlannedReminder> _hydration(
  DateTime now, {
  ArcRecords? records,
  ReminderPreferences? prefs,
  WinterArcSession? arc,
  DateTime? loggedAt,
}) => [
  for (final r in ReminderPlanner.plan(
    preferences: prefs ?? _prefs(),
    active: arc ?? activeSession(),
    now: now,
    hydration: _days(records ?? _records(), now, arc: arc, loggedAt: loggedAt),
  ))
    if (r.kind == ReminderKind.hydration) r,
];

List<HydrationCheckpoint> _checkpoints(
  LocalDate date,
  int target, {
  HydrationMode mode = HydrationMode.balanced,
  HydrationWindow window = HydrationWindow.defaults,
}) => HydrationPlanner.checkpointsFor(
  date: date,
  target: target,
  mode: mode,
  window: window,
);

int _minuteOfDay(DateTime t) => t.hour * 60 + t.minute;

void main() {
  group('modes and preferences', () {
    test('Gentle, Balanced and Supportive allow up to 3, 4 and 5 nudges; '
        'Balanced is the default', () {
      expect(
        {for (final m in HydrationMode.values) m.name: m.maxNudges},
        {'gentle': 3, 'balanced': 4, 'supportive': 5},
      );
      expect(
        ReminderPreferences.defaults.hydrationMode,
        HydrationMode.balanced,
      );
      expect(
        HydrationPlanner.maxNudgesPerDay,
        HydrationMode.values
            .map((m) => m.maxNudges)
            .reduce((a, b) => a > b ? a : b),
      );
    });

    test('stored names are stable', () {
      for (final mode in HydrationMode.values) {
        expect(HydrationMode.fromName(mode.name), mode);
      }
      expect(HydrationMode.fromName('Balanced'), isNull);
      expect(HydrationMode.fromName(null), isNull);
    });

    test('Hydration Coach is off by default, 08:00 – 20:00', () {
      const defaults = ReminderPreferences.defaults;
      expect(defaults.hydrationEnabled, isFalse);
      expect(defaults.hydrationWindow.start, _t(8, 0));
      expect(defaults.hydrationWindow.end, _t(20, 0));
      expect(defaults.anyEnabled, isFalse);
      expect(defaults.copyWith(hydrationEnabled: true).anyEnabled, isTrue);
    });

    test('the built-in Water template has the id Hydration Coach follows', () {
      final template = HabitTemplateCatalog.all.singleWhere(
        (t) => t.id == builtInWaterHabitId,
      );
      expect(template.type, HabitType.count);
      expect(template.starter, isTrue);
    });
  });

  group('active hours', () {
    test('a same-day window of 8 to 18 hours is valid', () {
      for (final (start, end) in [
        (_t(8, 0), _t(20, 0)),
        (_t(8, 0), _t(16, 0)), // exactly 8 hours
        (_t(5, 0), _t(23, 0)), // exactly 18 hours
        (_t(0, 0), _t(18, 0)),
        (_t(6, 0), _t(23, 59)),
        (_t(9, 15), _t(21, 45)),
      ]) {
        expect(HydrationWindow.isValid(start, end), isTrue, reason: '$start');
        expect(HydrationWindow(start, end).start, start);
      }
    });

    test('anything else is rejected by the domain', () {
      for (final (start, end) in [
        (_t(8, 0), _t(15, 59)), // 7 h 59
        (_t(5, 0), _t(23, 1)), // 18 h 01
        (_t(20, 0), _t(8, 0)), // end before start
        (_t(8, 0), _t(8, 0)), // empty
        (_t(22, 0), _t(6, 0)), // overnight
        (_t(0, 0), _t(23, 59)), // almost a day
      ]) {
        expect(HydrationWindow.isValid(start, end), isFalse, reason: '$start');
        expect(HydrationWindow.tryCreate(start, end), isNull);
        expect(
          () => HydrationWindow(start, end),
          throwsA(
            isA<DomainFailure>().having(
              (f) => f.rule,
              'rule',
              DomainRule.invalidHydrationWindow,
            ),
          ),
        );
      }
    });
  });

  group('checkpoints', () {
    final date = LocalDate(2026, 10, 14);

    test('Balanced, 08:00 – 20:00, target 8: four checkpoints near 09:48, '
        '12:48, 15:48 and 18:48, expecting 2, 4, 6 and 8', () {
      final checkpoints = _checkpoints(date, 8);
      expect(checkpoints.map((c) => c.expected), [2, 4, 6, 8]);
      expect(checkpoints.map((c) => c.slot), [0, 1, 2, 3]);
      const bases = [9 * 60 + 48, 12 * 60 + 48, 15 * 60 + 48, 18 * 60 + 48];
      for (final (i, checkpoint) in checkpoints.indexed) {
        expect(checkpoint.at.year, 2026);
        expect(LocalDate.fromDateTime(checkpoint.at), date);
        expect(
          (_minuteOfDay(checkpoint.at) - bases[i]).abs(),
          lessThanOrEqualTo(HydrationPlanner.maxJitterMinutes),
          reason: '${checkpoint.at}',
        );
      }
    });

    test('never more checkpoints than glasses: target 3 on Balanced gives 3, '
        'expecting 1, 2 and 3', () {
      expect(_checkpoints(date, 3).map((c) => c.expected), [1, 2, 3]);
    });

    test('target 2 and target 1', () {
      expect(_checkpoints(date, 2).map((c) => c.expected), [1, 2]);
      final single = _checkpoints(date, 1).single;
      expect(single.expected, 1);
      // Past the middle of the day (62.5 %: 15:30), not at the start.
      expect(
        (_minuteOfDay(single.at) - (15 * 60 + 30)).abs(),
        lessThanOrEqualTo(HydrationPlanner.maxJitterMinutes),
      );
    });

    test('target 8+ in every mode: the maximum count, the last expecting '
        'the whole target', () {
      expect(
        _checkpoints(
          date,
          8,
          mode: HydrationMode.gentle,
        ).map((c) => c.expected),
        [3, 6, 8],
      );
      expect(
        _checkpoints(
          date,
          8,
          mode: HydrationMode.supportive,
        ).map((c) => c.expected),
        [2, 4, 5, 7, 8],
      );
      expect(
        _checkpoints(
          date,
          12,
          mode: HydrationMode.supportive,
        ).map((c) => c.expected),
        [3, 5, 8, 10, 12],
      );
    });

    test('every valid window, mode, target and date: ordered, at least an '
        'hour apart, inside the window, ±15 minutes, no repeated '
        'expectation', () {
      final windows = [
        for (var start = 0; start < 24 * 60; start += 45)
          for (var end = start; end < 24 * 60; end += 45)
            ?HydrationWindow.tryCreate(
              _t(start ~/ 60, start % 60),
              _t(end ~/ 60, end % 60),
            ),
      ];
      expect(windows.length, greaterThan(100));
      final dates = [
        for (var i = 0; i < 40; i++) LocalDate(2026, 10, 1).addDays(i * 9),
      ];
      var checked = 0;
      for (final window in windows) {
        for (final mode in HydrationMode.values) {
          for (final target in [1, 2, 3, 4, 5, 8, 13]) {
            for (final date in dates) {
              final checkpoints = _checkpoints(
                date,
                target,
                mode: mode,
                window: window,
              );
              expect(checkpoints, isNotEmpty);
              expect(checkpoints.last.expected, target);
              for (final (i, c) in checkpoints.indexed) {
                final minute = _minuteOfDay(c.at);
                expect(minute, greaterThan(window.start.minuteOfDay));
                expect(minute, lessThan(window.end.minuteOfDay));
                if (i > 0) {
                  final previous = checkpoints[i - 1];
                  expect(
                    minute - _minuteOfDay(previous.at),
                    greaterThanOrEqualTo(60),
                  );
                  expect(c.expected, greaterThan(previous.expected));
                }
                checked++;
              }
            }
          }
        }
      }
      expect(checked, greaterThan(100000));
    });
  });

  group('deterministic daily variation', () {
    final date = LocalDate(2026, 10, 14);

    test('the same date and settings always give the same times', () {
      final first = _checkpoints(date, 8).map((c) => c.at).toList();
      for (var i = 0; i < 5; i++) {
        expect(_checkpoints(date, 8).map((c) => c.at), first);
      }
      // Re-planning later the same day (a resume) changes nothing either.
      final morning = _hydration(DateTime(2026, 10, 14, 7));
      final resumed = _hydration(DateTime(2026, 10, 14, 7, 30));
      expect(
        resumed.map((r) => (r.id, r.at)),
        morning.map((r) => (r.id, r.at)),
      );
    });

    test('times differ from day to day', () {
      final jitter = {
        for (var i = 0; i < 31; i++)
          HydrationPlanner.jitterMinutes(
            LocalDate(2026, 10, 1).addDays(i),
            HydrationMode.balanced,
            HydrationWindow.defaults,
            0,
          ),
      };
      expect(jitter.length, greaterThan(5));
      expect(jitter.every((j) => j.abs() <= 15), isTrue);
      expect(
        _checkpoints(LocalDate(2026, 10, 14), 8).map((c) => c.at.minute),
        isNot(_checkpoints(LocalDate(2026, 10, 15), 8).map((c) => c.at.minute)),
      );
    });

    test('a new mode or window gives a new, equally stable schedule', () {
      final window = HydrationWindow(_t(7, 0), _t(19, 0));
      final moved = _checkpoints(date, 8, window: window);
      expect(_checkpoints(date, 8, window: window).map((c) => c.at), [
        for (final c in moved) c.at,
      ]);
      expect(
        moved.map((c) => c.at),
        isNot(_checkpoints(date, 8).map((c) => c.at)),
      );
      final supportive = _checkpoints(date, 8, mode: HydrationMode.supportive);
      expect(
        _checkpoints(date, 8, mode: HydrationMode.supportive).map((c) => c.at),
        [for (final c in supportive) c.at],
      );
    });

    test('the hash is 32-bit FNV-1a, a published function', () {
      expect(HydrationPlanner.stableHash(''), 0x811c9dc5);
      expect(HydrationPlanner.stableHash('a'), 0xe40c292c);
      expect(HydrationPlanner.stableHash('foobar'), 0xbf9cf968);
      // Fixed values: a change here moves every user's schedule.
      expect(
        HydrationPlanner.jitterMinutes(
          LocalDate(2026, 10, 14),
          HydrationMode.balanced,
          HydrationWindow.defaults,
          0,
        ),
        HydrationPlanner.stableHash('2026-10-14|balanced|08:00|20:00|0') % 31 -
            15,
      );
    });
  });

  group('pacing', () {
    // Wed 14 Oct 2026, Day 14 of the arc.
    final today = LocalDate(2026, 10, 14);
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 10, 14, hour, minute);
    ArcRecords withWater(int value, {DayMode mode = DayMode.normal}) =>
        _records(
          progress: [
            if (value > 0)
              progress('water', today, value, completed: value >= 8),
          ],
          modes: {today: mode},
        );
    List<PlannedReminder> todayOnly(List<PlannedReminder> plan) => [
      for (final r in plan)
        if (LocalDate.fromDateTime(r.at) == today) r,
    ];

    test('off: nothing at all', () {
      expect(_hydration(at(7), prefs: _prefs(hydration: false)), isEmpty);
    });

    test('no running arc: nothing', () {
      expect(
        ReminderPlanner.plan(
          preferences: _prefs(),
          active: null,
          now: at(7),
          hydration: _days(_records(), at(7)),
        ),
        isEmpty,
      );
      expect(
        _hydration(
          at(7),
          arc: activeSession().copyWith(status: WinterArcStatus.completed),
        ),
        isEmpty,
      );
    });

    test('behind pace: every checkpoint still ahead is eligible', () {
      expect(todayOnly(_hydration(at(7), records: withWater(0))), hasLength(4));
      expect(todayOnly(_hydration(at(7), records: withWater(1))), hasLength(4));
    });

    test('ahead of pace: a checkpoint already met is suppressed', () {
      // 5 glasses meet the 2- and 4-glass checkpoints.
      final plan = todayOnly(_hydration(at(7), records: withWater(5)));
      expect(plan, hasLength(2));
      expect(plan.map((r) => r.id), [302, 303]);
    });

    test('complete: nothing more today, the next days unchanged', () {
      final plan = _hydration(at(7), records: withWater(8));
      expect(todayOnly(plan), isEmpty);
      expect(plan, hasLength(6 * 4));
    });

    test('a checkpoint that has passed is never planned again', () {
      final checkpoints = _checkpoints(today, 8);
      final afterSecond = checkpoints[1].at.add(const Duration(minutes: 1));
      final plan = todayOnly(_hydration(afterSecond, records: withWater(0)));
      expect(plan.map((r) => r.id), [302, 303]);
    });

    test('a checkpoint within 45 minutes of the last log is skipped, not '
        'moved; later ones stay', () {
      final first = _checkpoints(today, 8).first.at;
      final loggedAt = first.subtract(const Duration(minutes: 30));
      final plan = todayOnly(
        _hydration(loggedAt, records: withWater(1), loggedAt: loggedAt),
      );
      expect(plan.map((r) => r.id), [301, 302, 303]);
      expect(plan.map((r) => r.at), [
        for (final c in _checkpoints(today, 8).skip(1)) c.at,
      ]);

      final longAgo = first.subtract(const Duration(minutes: 46));
      expect(
        todayOnly(
          _hydration(longAgo, records: withWater(1), loggedAt: longAgo),
        ),
        hasLength(4),
      );
    });

    test('logging less later brings eligible checkpoints back', () {
      final ahead = todayOnly(_hydration(at(7), records: withWater(5)));
      final undone = todayOnly(_hydration(at(7), records: withWater(3)));
      expect(ahead, hasLength(2));
      expect(undone.map((r) => r.id), [301, 302, 303]);
    });

    test('Minimum Day paces against the minimum target', () {
      // 3 of 8 on a normal day: behind.
      expect(todayOnly(_hydration(at(7), records: withWater(3))), isNotEmpty);
      // The same 3 on a Minimum Day (minimum 3): complete.
      expect(
        todayOnly(
          _hydration(at(7), records: withWater(3, mode: DayMode.minimum)),
        ),
        isEmpty,
      );
      // 1 of 3 on a Minimum Day: three checkpoints, 1 already met.
      final minimum = todayOnly(
        _hydration(at(7), records: withWater(1, mode: DayMode.minimum)),
      );
      expect(minimum.map((r) => r.id), [301, 302]);
    });

    test('future days are planned from no progress, never as Minimum Days', () {
      final plan = _hydration(at(21), records: withWater(0));
      expect(todayOnly(plan), isEmpty, reason: 'after the window');
      expect(plan, hasLength(6 * 4));
      expect(
        plan.map((r) => LocalDate.fromDateTime(r.at)).toSet(),
        hasLength(6),
      );
    });
  });

  group('the arc\'s Water habit is authoritative', () {
    final now = DateTime(2026, 10, 14, 7);
    final today = LocalDate(2026, 10, 14);

    test('a renamed built-in Water habit still counts', () {
      final renamed = Habit(
        id: 'water',
        title: 'Morning Hydration',
        type: HabitType.count,
        target: 8,
        minimumTarget: 3,
        unit: 'glasses',
        iconKey: 'water',
        enabled: true,
        sortOrder: 0,
        createdAt: DateTime(2026, 10, 1),
      );
      expect(
        _hydration(now, records: _records(habits: [renamed])),
        hasLength(7 * 4),
      );
    });

    test('a custom habit called Water never counts', () {
      for (final title in ['Water', 'Water Intake', 'Drink Water']) {
        final custom = Habit(
          id: 'custom_0123456789abcdef0123456789abcdef',
          title: title,
          type: HabitType.count,
          target: 8,
          minimumTarget: 3,
          unit: 'glasses',
          iconKey: 'water',
          enabled: true,
          sortOrder: 0,
          createdAt: DateTime(2026, 10, 1),
        );
        expect(
          _hydration(now, records: _records(habits: [custom])),
          isEmpty,
          reason: title,
        );
      }
    });

    test('no Water habit, or Water turned off: nothing', () {
      expect(
        _hydration(now, records: _records(habits: [habit('workout')])),
        isEmpty,
      );
      expect(
        _hydration(
          now,
          records: _records(
            habits: [habit('water', target: 8, minimum: 3, enabled: false)],
          ),
        ),
        isEmpty,
      );
    });

    test('a goal change applies from its effective date only', () {
      // Water goes to 2 glasses from 17 Oct.
      final plan = _hydration(
        now,
        records: _records(
          revisions: [revision('water', LocalDate(2026, 10, 17), target: 2)],
        ),
      );
      final perDay = <LocalDate, int>{};
      for (final r in plan) {
        final date = LocalDate.fromDateTime(r.at);
        perDay[date] = (perDay[date] ?? 0) + 1;
      }
      expect(perDay, {
        for (var i = 0; i < 7; i++) today.addDays(i): i < 3 ? 4 : 2,
      });
    });

    test('Water turned off by a revision gets nothing on those dates, and '
        'resumes when it is turned back on', () {
      final plan = _hydration(
        now,
        records: _records(
          revisions: [
            revision(
              'water',
              LocalDate(2026, 10, 16),
              target: 8,
              enabled: false,
            ),
            revision('water', LocalDate(2026, 10, 18), target: 8, minimum: 3),
          ],
        ),
      );
      final dates = plan.map((r) => LocalDate.fromDateTime(r.at)).toSet();
      expect(dates, {
        today,
        today.addDays(1),
        for (var i = 4; i < 7; i++) today.addDays(i),
      });
    });
  });

  group('participation', () {
    test('nothing before a seasonal arc is joined or after its last day', () {
      final seasonal = WinterArcSession(
        id: 1,
        kind: ArcKind.seasonalWinter,
        startDate: LocalDate(2026, 10, 1),
        endDate: LocalDate(2026, 12, 31),
        participationStartDate: LocalDate(2026, 10, 16),
        status: WinterArcStatus.active,
        createdAt: DateTime(2026, 9, 20),
        startedAt: DateTime(2026, 10, 16),
      );
      final early = _hydration(DateTime(2026, 10, 14, 7), arc: seasonal);
      expect(early.map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
        for (var i = 2; i < 7; i++) LocalDate(2026, 10, 14).addDays(i),
      });
      final late = _hydration(DateTime(2026, 12, 29, 7), arc: seasonal);
      expect(late.map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
        LocalDate(2026, 12, 29),
        LocalDate(2026, 12, 30),
        LocalDate(2026, 12, 31),
      });
    });

    test('the local date decides "today": just before and after midnight', () {
      final before = _hydration(DateTime(2026, 10, 14, 23, 59));
      final after = _hydration(DateTime(2026, 10, 15, 0, 1));
      // 23:59: today's window is over; tomorrow is offset 1 (ids 31x).
      expect(before.first.id, 310);
      expect(LocalDate.fromDateTime(before.first.at), LocalDate(2026, 10, 15));
      // After midnight the same checkpoint is today's (ids 30x), same time.
      expect(after.first.id, 300);
      expect(after.first.at, before.first.at);
      expect(
        after.map((r) => LocalDate.fromDateTime(r.at)).toSet(),
        hasLength(7),
      );
    });
  });

  group('notifications', () {
    final now = DateTime(2026, 10, 14, 6);

    test('a 7-day horizon, ids unique and clear of the other kinds', () {
      final plan = ReminderPlanner.plan(
        preferences: _prefs(
          daily: true,
          reflection: true,
          mode: HydrationMode.supportive,
        ),
        active: activeSession(),
        now: now,
        hydration: _days(_records(), now),
      );
      final hydration = plan.where((r) => r.kind == ReminderKind.hydration);
      expect(hydration, hasLength(7 * 5));
      expect(
        hydration.map((r) => LocalDate.fromDateTime(r.at)).toSet(),
        hasLength(HydrationPlanner.horizonDays),
      );
      expect(plan.map((r) => r.id).toSet(), hasLength(plan.length));
      expect(hydration.every((r) => r.id >= 300 && r.id < 365), isTrue);
      expect(
        plan
            .where((r) => r.kind != ReminderKind.hydration)
            .every((r) => r.id < 300),
        isTrue,
      );
    });

    test('ids depend only on the day offset and slot', () {
      final first = _hydration(now);
      final again = _hydration(now.add(const Duration(minutes: 10)));
      expect(again.map((r) => r.id), first.map((r) => r.id));
      expect(first.take(4).map((r) => r.id), [300, 301, 302, 303]);
      expect(first.last.id, 363);
    });

    test('worst case: everything on, Supportive, Water 8, full horizon: 63 '
        'pending at most, within iOS\'s 64', () {
      var most = 0;
      for (final hour in [0, 6, 9]) {
        final at = DateTime(2026, 10, 14, hour);
        final plan = ReminderPlanner.plan(
          preferences: _prefs(
            daily: true,
            reflection: true,
            mode: HydrationMode.supportive,
          ),
          active: activeSession(),
          now: at,
          hydration: _days(_records(), at),
        );
        if (plan.length > most) most = plan.length;
      }
      expect(most, 63);
      expect(ReminderPlanner.maxPending, 63);
      expect(ReminderPlanner.maxPending, lessThan(64));
      // Even if the service handed over more days, only seven are planned.
      final extra = [
        for (var offset = 0; offset < 14; offset++)
          HydrationDay.of(
            arc: activeSession(),
            records: _records(),
            date: LocalDate(2026, 10, 14).addDays(offset),
          ),
      ];
      final plan = ReminderPlanner.plan(
        preferences: _prefs(
          daily: true,
          reflection: true,
          mode: HydrationMode.supportive,
        ),
        active: activeSession(),
        now: now,
        hydration: extra,
      );
      expect(plan.length, lessThanOrEqualTo(63));
    });

    test('daily and reflection reminders are exactly as before', () {
      const both = ReminderPreferences(
        dailyEnabled: true,
        dailyTime: ReminderTime(8, 30),
        reflectionEnabled: true,
        reflectionTime: ReminderTime(21, 15),
      );
      final without = ReminderPlanner.plan(
        preferences: both,
        active: activeSession(),
        now: now,
      );
      final withHydration = ReminderPlanner.plan(
        preferences: both.copyWith(hydrationEnabled: true),
        active: activeSession(),
        now: now,
        hydration: _days(_records(), now),
      );
      String key(PlannedReminder r) =>
          '${r.id} ${r.kind.payload} ${r.at} ${r.title} ${r.body}';
      expect(
        withHydration
            .where((r) => r.kind != ReminderKind.hydration)
            .map(key)
            .toList(),
        without.map(key).toList(),
      );
      expect(without, hasLength(28));
    });

    test('generic copy: no amounts, targets or habit names; opens Today', () {
      final plan = _hydration(now);
      for (final r in plan) {
        expect(r.title, 'Hydration check');
        expect(r.body, 'A little water now can keep you on pace.');
        expect(r.payload, 'hydration');
        expect(RegExp(r'\d').hasMatch('${r.title}${r.body}'), isFalse);
      }
      expect(ReminderKind.fromPayload('hydration'), ReminderKind.hydration);
      expect(ReminderKind.daily.payload, 'today');
      expect(ReminderKind.reflection.payload, 'journal');
    });
  });

  group('ReminderChanges', () {
    PlannedReminder r(int id, int minute, {ReminderKind? kind}) =>
        PlannedReminder(
          id: id,
          kind: kind ?? ReminderKind.hydration,
          at: DateTime(2026, 10, 14, 10, minute),
          title: 'Hydration check',
          body: 'A little water now can keep you on pace.',
        );

    test('only what changed is cancelled or rescheduled', () {
      final known = {
        for (final x in [r(100, 0), r(300, 0), r(301, 5)]) x.id: x,
      };
      final changes = ReminderChanges.between(
        pending: {100, 300, 301},
        known: known,
        next: [r(100, 0), r(301, 6), r(302, 0)],
      );
      expect(changes.cancel, [300]);
      expect(changes.schedule.map((x) => (x.id, x.at.minute)), [
        (301, 6),
        (302, 0),
      ]);
    });

    test('an unknown or no longer pending id is scheduled again', () {
      final changes = ReminderChanges.between(
        pending: {300},
        known: {301: r(301, 0)},
        next: [r(300, 0), r(301, 0)],
      );
      expect(changes.cancel, isEmpty);
      expect(changes.schedule.map((x) => x.id), [300, 301]);
    });

    test('an empty plan cancels every pending id', () {
      final changes = ReminderChanges.between(
        pending: {100, 200, 300},
        known: const {},
        next: const [],
      );
      expect(changes.cancel, [100, 200, 300]);
      expect(changes.schedule, isEmpty);
    });
  });
}
