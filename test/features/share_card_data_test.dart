import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/features/share/share_card_data.dart';

import '../support/builders.dart';
import '../support/share_fixtures.dart';

/// Phase 10B: the share card snapshots carry exactly the persisted facts
/// they show, and nothing a privacy switch hid or that is never shared.

/// Every string a Today card can put into the image, its semantics, its
/// file name or its accompanying text.
List<String> _todayStrings(TodayShareCardData data) => [
  data.headline,
  data.dayLabel,
  data.tagline,
  data.fileName,
  data.shareText,
  data.semanticsLabel,
  for (final habit in data.habits) ...[?habit.title, ?habit.iconKey],
  if (data.streak case final streak?) ...[streak.label, streak.daysLabel],
];

List<String> _arcStrings(ArcShareCardData data) => [
  data.headline,
  data.subtitle,
  data.startLabel,
  data.endLabel,
  data.tagline,
  data.fileName,
  data.shareText,
  data.semanticsLabel,
  for (final goal in data.goals) ...[goal.title, goal.target],
];

AchievementBoard _board({
  Map<AchievementKey, int> unlockedOnDay = const {},
  LocalDate? start,
}) {
  final day1 = start ?? LocalDate(2026, 10, 1);
  return AchievementBoard(
    startDate: day1,
    entries: [
      for (final definition in AchievementCatalog.all)
        AchievementStatus(
          definition: definition,
          unlock: switch (unlockedOnDay[definition.key]) {
            final day? => AchievementUnlock(
              key: definition.key,
              unlockedOn: day1.addDays(day - 1),
              unlockedAt: day1.addDays(day - 1).toLocalDateTime(),
            ),
            null => null,
          },
        ),
    ],
  );
}

AchievementStatus _status(AchievementBoard board, AchievementKey key) =>
    board.entries.firstWhere((e) => e.definition.key == key);

void main() {
  group("Today's Progress", () {
    test('1. carries the arc kind and challenge day', () {
      final rolling = TodayShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 4), today: 24),
      );
      expect(rolling.arc.seasonal, isFalse);
      expect(rolling.dayNumber, 24);
      expect(rolling.headline, 'WINTER ARC · DAY 24 OF 92');
      expect(rolling.fileName, 'nextrep-day-24.png');

      final seasonal = TodayShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: 4),
          today: 40,
          session: seasonalSession(joinDay: 15),
        ),
      );
      expect(seasonal.arc.seasonal, isTrue);
      // Day numbers count from 1 October, also for a late joiner.
      expect(seasonal.headline, 'SEASONAL WINTER ARC · DAY 40 OF 92');
    });

    test('2. carries the persisted completed / total count', () {
      final data = TodayShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: 7),
          done: {'water', 'workout', 'learning', 'english', 'meditation'},
        ),
      );
      expect((data.completed, data.total), (5, 7));
      expect(data.semanticsLabel, contains('5 of 7 habits complete'));
    });

    test('3. a Minimum Day is shown as one, never as a Perfect Day', () {
      final habits = catalogHabits(count: 4);
      final minimum = TodayShareCardData.fromSummary(
        shareSummary(
          habits: habits,
          done: {for (final h in habits) h.id},
          mode: DayMode.minimum,
        ),
      );
      expect(minimum.minimumDay, isTrue);
      expect(minimum.perfectDay, isFalse);
      expect((minimum.completed, minimum.total), (4, 4));
      expect(minimum.semanticsLabel, isNot(contains('Perfect')));

      final perfect = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: {for (final h in habits) h.id}),
      );
      expect((perfect.minimumDay, perfect.perfectDay), (false, true));
    });

    test('4 / 5. lists all 12 habits in order with accurate status', () {
      final habits = catalogHabits(count: 12);
      final done = {'water', 'sleep_before', 'custom_9', 'custom_10'};
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: done),
      );
      expect(data.habits, hasLength(12));
      expect(
        [for (final h in data.habits) h.title],
        [for (final h in habits) h.title],
      );
      expect(
        [for (final h in data.habits) h.done],
        [for (final h in habits) done.contains(h.id)],
      );
    });

    test('6. habit names off removes every habit title and icon', () {
      final habits = catalogHabits(count: 12, customTitle: 'Secret Habit');
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: {'water'}, streakDays: 2),
        privacy: const SharePrivacyOptions(habitNames: false),
      );
      expect(data.showsHabitNames, isFalse);
      expect(
        data.habits.every((h) => h.title == null && h.iconKey == null),
        isTrue,
      );
      // The count stays.
      expect((data.completed, data.total), (1, 12));
      final all = _todayStrings(data).join('\n');
      for (final habit in habits) {
        expect(all, isNot(contains(habit.title)));
      }
    });

    test('7. XP & level off removes both', () {
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 4), xp: 1080),
        privacy: const SharePrivacyOptions(xpAndLevel: false),
      );
      expect((data.level, data.totalXp), (null, null));
      final all = _todayStrings(data).join('\n');
      expect(all, isNot(contains('1080')));
      expect(all, isNot(contains('XP')));
      expect(all, isNot(contains('Level')));

      final shown = TodayShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 4), xp: 1080),
      );
      expect((shown.level, shown.totalXp), (5, 1080));
    });

    test('8. streak off removes it; on, it is honestly named', () {
      final habits = catalogHabits(count: 4);
      final perfect = TodayShareCardData.fromSummary(
        shareSummary(
          habits: habits,
          done: {for (final h in habits) h.id},
          streakDays: 6,
        ),
      );
      expect(perfect.streak?.label, 'Perfect Day streak');
      expect(perfect.streak?.days, 7);

      // No Perfect Day run, but one habit has a run: its streak, named so.
      final habitRun = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: {'water'}),
      );
      expect(habitRun.streak?.label, 'Best active habit streak');
      expect(habitRun.streak?.daysLabel, '1 day');

      final hidden = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: {'water'}, streakDays: 6),
        privacy: const SharePrivacyOptions(streak: false),
      );
      expect(hidden.streak, isNull);
      expect(_todayStrings(hidden).join('\n'), isNot(contains('streak')));

      expect(
        TodayShareCardData.fromSummary(shareSummary(habits: habits)).streak,
        isNull,
      );
    });

    test('9. last night\'s bedtime is never on the card', () {
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 6), done: {'sleep_before'}),
      );
      final sleep = data.habits.firstWhere(
        (h) => h.title == 'Sleep Before Target',
      );
      expect(sleep.done, isTrue);
      final all = _todayStrings(data).join('\n');
      expect(all, isNot(contains(loggedBedtime.hhmm)));
      expect(all, isNot(contains('23:30')));
      // No clock time of any kind.
      expect(RegExp(r'\d{1,2}:\d{2}').hasMatch(all), isFalse);
    });

    test('10. no Journal, reflection or mood fields exist on the card', () {
      // The card is built from DaySummary alone, which carries no
      // reflection data; a habit can't smuggle it in either.
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 8), done: {'journal'}),
      );
      final all = _todayStrings(data).join('\n');
      expect(all, isNot(contains(privateNote)));
      expect(all.toLowerCase(), isNot(contains('mood')));
      expect(all.toLowerCase(), isNot(contains('reflection')));
    });

    test('the accompanying text names the arc and day only', () {
      final habits = catalogHabits(count: 6);
      final data = TodayShareCardData.fromSummary(
        shareSummary(habits: habits, done: {'water'}, xp: 1080, today: 24),
      );
      expect(data.shareText, 'My Winter Arc · Day 24/92 — NextRep');
      for (final habit in habits) {
        expect(data.shareText, isNot(contains(habit.title)));
      }
      expect(data.shareText, isNot(contains('?')));
    });
  });

  group('My Arc', () {
    test('11. only habits enabled today', () {
      final habits = [
        ...catalogHabits(count: 3),
        catalogHabits(count: 4)[3].copyWith(enabled: false),
      ];
      final data = ArcShareCardData.fromSummary(shareSummary(habits: habits));
      expect(
        [for (final g in data.goals) g.title],
        ['Workout', 'Water Intake', 'Learning / Skills'],
      );
    });

    test('12. full targets, never Minimum Day targets', () {
      final data = ArcShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 2), mode: DayMode.minimum),
      );
      expect([for (final g in data.goals) g.target], ['30 min', '8 glasses']);
    });

    test('13 / 14 / 15 / 16. target labels per habit type', () {
      final data = ArcShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 12)),
      );
      String target(String title) =>
          data.goals.firstWhere((g) => g.title == title).target;
      expect(target('Water Intake'), '8 glasses'); // count
      expect(target('Workout'), '30 min'); // duration
      expect(target('No Junk Food'), 'Daily goal'); // binary
      expect(target('Sleep Before Target'), 'Before 23:30'); // timeBefore
    });

    test('a goal edit saved for tomorrow is not shown yet', () {
      final data = ArcShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: 2),
          today: 5,
          revisions: [revision('water', dayN(6), target: 12, minimum: 4)],
        ),
      );
      expect(data.goals[1].target, '8 glasses');
    });

    test('17. rolling vs seasonal wording', () {
      final rolling = ArcShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 2)),
      );
      expect(rolling.headline, 'MY 92-DAY WINTER ARC');
      expect(rolling.subtitle, 'Rolling 92-day Arc');
      expect(rolling.shareText, 'My 92-day Winter Arc — NextRep');

      final seasonal = ArcShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: 2),
          session: seasonalSession(),
        ),
      );
      expect(seasonal.headline, 'MY SEASONAL WINTER ARC');
      expect(seasonal.subtitle, 'Winter season 2026 · 92 days');
      expect(seasonal.startLabel, 'DAY 1');
      expect(seasonal.shareText, 'My Seasonal Winter Arc — NextRep');
    });

    test('18. a late seasonal join never claims Day 1', () {
      final data = ArcShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: 2),
          today: 20,
          session: seasonalSession(joinDay: 15),
        ),
      );
      expect(data.startLabel, 'JOINED DAY 15');
      expect(data.endLabel, 'DAY 92');
      expect(_arcStrings(data).join('\n'), isNot(contains('DAY 1 ')));
      // No calendar dates.
      expect(_arcStrings(data).join('\n'), isNot(contains('Oct')));
    });

    test('19 / 20. supports 12 habits, long custom names kept whole', () {
      final title = 'A' * 40;
      final data = ArcShareCardData.fromSummary(
        shareSummary(habits: catalogHabits(count: 12, customTitle: title)),
      );
      expect(data.goals, hasLength(12));
      expect(data.goals.last.title, title);
    });
  });

  group('Achievement', () {
    test('21 / 22. title, criterion and challenge day of the unlock', () {
      final board = _board(unlockedOnDay: {AchievementKey.streak7: 12});
      final data = AchievementShareCardData.of(
        _status(board, AchievementKey.streak7),
        board,
      )!;
      expect(data.title, 'Cold Front');
      expect(data.description, 'Reach a 7-day streak on any habit.');
      expect(data.dayNumber, 12);
      expect(data.unlockedLabel, 'UNLOCKED · DAY 12');
      expect(data.fileName, 'nextrep-achievement-cold-front.png');
      expect(data.shareText, 'Achievement unlocked: Cold Front — NextRep');
    });

    test('23. no calendar date', () {
      final board = _board(unlockedOnDay: {AchievementKey.firstRep: 12});
      final data = AchievementShareCardData.of(
        _status(board, AchievementKey.firstRep),
        board,
      )!;
      final all = [
        data.title,
        data.description,
        data.unlockedLabel,
        data.tagline,
        data.fileName,
        data.shareText,
        data.semanticsLabel,
      ].join('\n');
      for (final date in ['12 Oct', 'Oct 12', '2026-10-12', '12/10']) {
        expect(all, isNot(contains(date)));
      }
    });

    test('24. a locked achievement produces no card', () {
      final board = _board();
      for (final status in board.entries) {
        expect(AchievementShareCardData.of(status, board), isNull);
      }
    });

    test('25. a reflection achievement shares its criterion, not text', () {
      final board = _board(unlockedOnDay: {AchievementKey.firstReflection: 3});
      final data = AchievementShareCardData.of(
        _status(board, AchievementKey.firstReflection),
        board,
      )!;
      expect(data.semanticsLabel, isNot(contains(privateNote)));
      expect(data.shareText, isNot(contains(privateNote)));
    });
  });

  test('no card carries a link: share text names NextRep only', () {
    final habits = catalogHabits(count: 12);
    final board = _board(
      unlockedOnDay: {for (final d in AchievementCatalog.all) d.key: 5},
    );
    final everything = [
      ..._todayStrings(
        TodayShareCardData.fromSummary(
          shareSummary(habits: habits, done: {'water'}, today: 24),
        ),
      ),
      ..._todayStrings(
        TodayShareCardData.fromSummary(
          shareSummary(
            habits: habits,
            session: seasonalSession(joinDay: 15),
            today: 30,
          ),
        ),
      ),
      ..._arcStrings(
        ArcShareCardData.fromSummary(shareSummary(habits: habits)),
      ),
      ..._arcStrings(
        ArcShareCardData.fromSummary(
          shareSummary(habits: habits, session: seasonalSession()),
        ),
      ),
      for (final status in board.entries) ...[
        AchievementShareCardData.of(status, board)!.shareText,
        AchievementShareCardData.of(status, board)!.semanticsLabel,
      ],
    ];
    for (final text in everything) {
      for (final link in ['github', 'http://', 'https://', 'www.', '.com']) {
        expect(text.toLowerCase(), isNot(contains(link)), reason: text);
      }
      expect(text, isNot(contains('arunachaleswaranms')), reason: text);
      expect(text, isNot(contains('?')), reason: text);
    }
  });

  test('file name pieces are sanitized', () {
    expect(shareFileSlug('Cold Front'), 'cold-front');
    expect(shareFileSlug('../../etc/passwd'), 'etc-passwd');
    expect(shareFileSlug('Ten Clean Sweeps!'), 'ten-clean-sweeps');
    expect(shareFileSlug('Ünïcödé ★'), 'n-c-d');
    expect(shareFileSlug('★★★'), 'card');
    expect(shareFileSlug('x' * 80), hasLength(40));
  });

  test('every catalog achievement has a safe file name', () {
    for (final definition in AchievementCatalog.all) {
      expect(
        AchievementShareCardData(
          key: definition.key,
          title: definition.title,
          description: definition.description,
          dayNumber: 1,
        ).fileName,
        matches(RegExp(r'^nextrep-achievement-[a-z0-9]+(-[a-z0-9]+)*\.png$')),
      );
    }
  });
}
