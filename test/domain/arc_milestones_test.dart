import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/journey/arc_milestones.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

void main() {
  group('ArcMilestone.forDay', () {
    const expected = {
      1: ArcMilestone.frozenTrail,
      6: ArcMilestone.frozenTrail,
      7: ArcMilestone.firstCamp,
      13: ArcMilestone.firstCamp,
      14: ArcMilestone.forestCamp,
      29: ArcMilestone.forestCamp,
      30: ArcMilestone.ridge,
      44: ArcMilestone.ridge,
      45: ArcMilestone.aurora,
      59: ArcMilestone.aurora,
      60: ArcMilestone.highRidge,
      74: ArcMilestone.highRidge,
      75: ArcMilestone.summitShelter,
      91: ArcMilestone.summitShelter,
      92: ArcMilestone.summit,
    };
    for (final MapEntry(key: day, value: milestone) in expected.entries) {
      test('Day $day is ${milestone.name}', () {
        expect(ArcMilestone.forDay(day), milestone);
      });
    }

    test('never leaves the arc', () {
      expect(ArcMilestone.forDay(0), ArcMilestone.frozenTrail);
      expect(ArcMilestone.forDay(-5), ArcMilestone.frozenTrail);
      expect(ArcMilestone.forDay(93), ArcMilestone.summit);
      expect(ArcMilestone.forDay(500), ArcMilestone.summit);
      for (final m in ArcMilestone.values) {
        expect(m.day, inInclusiveRange(1, WinterArcRules.lengthInDays));
      }
      expect(ArcMilestone.summit.day, WinterArcRules.lengthInDays);
      expect(ArcMilestone.summit.next, isNull);
      expect(ArcMilestone.frozenTrail.next, ArcMilestone.firstCamp);
    });

    test('milestones are in day order and reached cumulatively', () {
      final days = ArcMilestone.values.map((m) => m.day).toList();
      expect(days, [1, 7, 14, 30, 45, 60, 75, 92]);
      expect(ArcMilestone.aurora.reachedBy(44), isFalse);
      expect(ArcMilestone.aurora.reachedBy(45), isTrue);
      expect(ArcMilestone.firstCamp.reachedBy(92), isTrue);
    });
  });

  group('JourneyChapter', () {
    test('chapters cover every day of the arc exactly once', () {
      var next = 1;
      for (final chapter in JourneyChapter.values) {
        expect(chapter.firstDay, next);
        expect(chapter.lastDay, greaterThanOrEqualTo(chapter.firstDay));
        next = chapter.lastDay + 1;
      }
      expect(next - 1, WinterArcRules.lengthInDays);
      expect(
        JourneyChapter.values.fold(0, (sum, c) => sum + c.length),
        WinterArcRules.lengthInDays,
      );
    });

    test('forDay maps boundaries and clamps to the arc', () {
      expect(JourneyChapter.forDay(1), JourneyChapter.frozenForest);
      expect(JourneyChapter.forDay(14), JourneyChapter.frozenForest);
      expect(JourneyChapter.forDay(15), JourneyChapter.firstAscent);
      expect(JourneyChapter.forDay(31), JourneyChapter.ridge);
      expect(JourneyChapter.forDay(46), JourneyChapter.auroraPass);
      expect(JourneyChapter.forDay(61), JourneyChapter.highMountain);
      expect(JourneyChapter.forDay(76), JourneyChapter.summitApproach);
      expect(JourneyChapter.forDay(92), JourneyChapter.summitApproach);
      expect(JourneyChapter.forDay(120), JourneyChapter.summitApproach);
      expect(JourneyChapter.forDay(0), JourneyChapter.frozenForest);
    });
  });
}
