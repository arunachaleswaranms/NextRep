import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/progress/streak_rules.dart';

const hit = StreakMark.hit;
const miss = StreakMark.miss;
const skip = StreakMark.skip;
const pending = StreakMark.pending;

Streak _of(List<StreakMark> marks) => StreakRules.compute(marks);

void main() {
  test('no days is no streak', () {
    expect(_of([]), Streak.none);
  });

  test('consecutive hits build the current and best streak', () {
    expect(_of([hit, hit, hit]), const Streak(current: 3, best: 3));
  });

  test('a miss resets the current streak but keeps the best', () {
    expect(_of([hit, hit, hit, miss, hit]), const Streak(current: 1, best: 3));
    expect(_of([hit, hit, miss]), const Streak(current: 0, best: 2));
  });

  test('skipped (not applicable) days neither count nor break', () {
    expect(_of([hit, skip, skip, hit]), const Streak(current: 2, best: 2));
    expect(_of([skip, skip]), Streak.none);
  });

  test('today pending keeps yesterday\'s streak alive', () {
    expect(_of([hit, hit, pending]), const Streak(current: 2, best: 2));
  });

  test('best is the longest run anywhere', () {
    expect(
      _of([hit, hit, hit, hit, miss, hit, hit, pending]),
      const Streak(current: 2, best: 4),
    );
  });
}
