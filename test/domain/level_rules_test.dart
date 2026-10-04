import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/xp/level_rules.dart';

void main() {
  test('levels are 250 XP apart, starting at level 1', () {
    expect(LevelRules.xpPerLevel, 250);
    expect(LevelRules.levelFor(0), 1);
    expect(LevelRules.levelFor(249), 1);
    expect(LevelRules.levelFor(250), 2);
    expect(LevelRules.levelFor(499), 2);
    expect(LevelRules.levelFor(500), 3);
    expect(LevelRules.levelFor(750), 4);
  });

  test('negative totals are treated as zero', () {
    expect(LevelRules.levelFor(-10), 1);
    expect(LevelRules.progressFor(-10).totalXp, 0);
  });

  group('progress within a level', () {
    test('at the start of a level', () {
      final p = LevelRules.progressFor(250);
      expect(p.level, 2);
      expect(p.levelStartXp, 250);
      expect(p.nextLevelXp, 500);
      expect(p.xpIntoLevel, 0);
      expect(p.xpForLevel, 250);
      expect(p.xpToNextLevel, 250);
      expect(p.ratio, 0);
    });

    test('just below the next level', () {
      final p = LevelRules.progressFor(249);
      expect(p.level, 1);
      expect(p.xpIntoLevel, 249);
      expect(p.xpToNextLevel, 1);
      expect(p.ratio, closeTo(0.996, 0.001));
    });

    test('mid level', () {
      final p = LevelRules.progressFor(375);
      expect(p.level, 2);
      expect(p.xpIntoLevel, 125);
      expect(p.ratio, 0.5);
    });
  });

  group('level up detection', () {
    test('crossing a boundary reports the new level', () {
      expect(LevelRules.levelUp(beforeXp: 240, afterXp: 255), 2);
      expect(LevelRules.levelUp(beforeXp: 249, afterXp: 250), 2);
    });

    test('crossing several boundaries reports the highest', () {
      expect(LevelRules.levelUp(beforeXp: 200, afterXp: 760), 4);
    });

    test('no boundary, or going down, is not a level up', () {
      expect(LevelRules.levelUp(beforeXp: 0, afterXp: 249), isNull);
      expect(LevelRules.levelUp(beforeXp: 255, afterXp: 240), isNull);
      expect(LevelRules.levelUp(beforeXp: 250, afterXp: 250), isNull);
    });
  });
}
