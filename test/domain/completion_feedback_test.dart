import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app_restart.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/feedback/completion_feedback.dart';
import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';

import '../support/fakes.dart';
import '../support/sound_fakes.dart';

/// The completion-sound engine (ARC_CONTROL_SPEC § 8.1–8.2, addendum § L5
/// "U"): throttle, Perfect Day, sound-off, failures. Pure Dart with a fake
/// player and a hand-moved monotonic clock.
void main() {
  late FakeSoundPlayer player;
  late FakeFeedbackPreferences preferences;
  late FakeMonotonic clock;
  late CompletionFeedback feedback;
  final today = LocalDate(2026, 11, 23);

  setUp(() {
    player = FakeSoundPlayer();
    preferences = FakeFeedbackPreferences();
    clock = FakeMonotonic();
    feedback = CompletionFeedback(
      preferences: preferences,
      player: player,
      elapsed: clock.call,
    );
  });

  Future<SoundOutcome> complete(
    String habit, {
    int arc = 1,
    LocalDate? date,
    bool perfect = false,
    Duration? requestedAt,
  }) => feedback.habitCompleted(
    sessionId: arc,
    date: date ?? today,
    habitId: habit,
    perfectDay: perfect,
    requestedAt: requestedAt ?? clock.now,
  );

  const ms = Duration(milliseconds: 1);

  test('a completion plays the selected set\'s habit sound, once', () async {
    expect(await complete('water'), SoundOutcome.playedHabit);
    expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);

    preferences.value = const FeedbackPreferences(
      soundsEnabled: true,
      soundTheme: SoundTheme.warmEmber,
    );
    clock.advance(const Duration(seconds: 1));
    expect(await complete('reading'), SoundOutcome.playedHabit);
    expect(player.plays.last, (SoundTheme.warmEmber, CompletionSound.habit));
  });

  group('sounds off', () {
    setUp(() {
      preferences.value = const FeedbackPreferences(
        soundsEnabled: false,
        soundTheme: SoundTheme.summitSpark,
      );
    });

    test('the player is never asked to play or load', () async {
      await feedback.warmUp();
      expect(await complete('water'), SoundOutcome.disabled);
      expect(await complete('x', perfect: true), SoundOutcome.disabled);
      expect(
        await feedback.preview(SoundTheme.iceCrystal),
        SoundOutcome.disabled,
      );
      expect(player.plays, isEmpty);
      expect(player.prepares, 0);
    });

    test('turning sounds back on applies to the next completion', () async {
      expect(await complete('water'), SoundOutcome.disabled);
      preferences.value = const FeedbackPreferences(
        soundsEnabled: true,
        soundTheme: SoundTheme.summitSpark,
      );
      clock.advance(ms);
      expect(await complete('water'), SoundOutcome.playedHabit);
      expect(player.plays, [(SoundTheme.summitSpark, CompletionSound.habit)]);
    });
  });

  group('global throttle: one sound per 500 ms, never overlapping', () {
    test('a second habit within 500 ms is dropped', () async {
      expect(await complete('a'), SoundOutcome.playedHabit);
      clock.advance(const Duration(milliseconds: 499));
      expect(await complete('b'), SoundOutcome.throttledGlobally);
      clock.advance(ms);
      expect(await complete('c'), SoundOutcome.playedHabit);
      expect(player.plays, hasLength(2));
    });

    test(
      'nothing starts while a Perfect Day sound (900 ms) still plays',
      () async {
        expect(
          await complete('a', perfect: true),
          SoundOutcome.playedPerfectDay,
        );
        clock.advance(const Duration(milliseconds: 899));
        expect(await complete('b'), SoundOutcome.throttledGlobally);
        clock.advance(ms);
        expect(await complete('c'), SoundOutcome.playedHabit);
      },
    );

    test('Summit Spark (450 ms) still waits the full 500 ms', () async {
      preferences.value = const FeedbackPreferences(
        soundsEnabled: true,
        soundTheme: SoundTheme.summitSpark,
      );
      await complete('a');
      clock.advance(const Duration(milliseconds: 470));
      expect(await complete('b'), SoundOutcome.throttledGlobally);
    });

    test('a dropped sound is never played later (nothing is queued)', () async {
      await complete('a');
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(milliseconds: 20));
        await complete('h$i');
      }
      expect(player.plays, hasLength(1));
      clock.advance(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      expect(player.plays, hasLength(1));
    });

    test('simultaneous completions: exactly one passes', () async {
      final outcomes = await Future.wait([
        for (var i = 0; i < 8; i++) complete('h$i'),
      ]);
      expect(outcomes.where((o) => o.played), hasLength(1));
      expect(player.plays, hasLength(1));
    });

    test('over a burst of rapid taps, plays are ≥ 500 ms and one sound '
        'length apart', () async {
      final started = <Duration>[];
      for (var i = 0; i < 200; i++) {
        clock.advance(const Duration(milliseconds: 37));
        final perfect = i % 17 == 0;
        final outcome = await complete(
          'h${i % 5}',
          perfect: perfect,
          date: today.addDays(i),
        );
        if (outcome.played) started.add(clock.now);
      }
      expect(started.length, greaterThan(5));
      for (var i = 1; i < started.length; i++) {
        expect(
          started[i] - started[i - 1],
          greaterThanOrEqualTo(const Duration(milliseconds: 500)),
        );
      }
    });
  });

  group('per-habit throttle: one sound per habit per 3 s', () {
    test('the same habit again within 3 s is dropped', () async {
      expect(await complete('water'), SoundOutcome.playedHabit);
      clock.advance(const Duration(milliseconds: 2999));
      expect(await complete('water'), SoundOutcome.throttledForHabit);
      clock.advance(ms);
      expect(await complete('water'), SoundOutcome.playedHabit);
    });

    test('other habits are not held back by it', () async {
      await complete('water');
      clock.advance(const Duration(milliseconds: 600));
      expect(await complete('reading'), SoundOutcome.playedHabit);
    });

    test('a dropped repeat does not extend the window', () async {
      await complete('water');
      clock.advance(const Duration(seconds: 2));
      expect(await complete('water'), SoundOutcome.throttledForHabit);
      clock.advance(const Duration(seconds: 1));
      expect(await complete('water'), SoundOutcome.playedHabit);
    });

    test('the same habit id in another Arc is another habit', () async {
      await complete('water', arc: 1);
      clock.advance(const Duration(milliseconds: 600));
      expect(await complete('water', arc: 2), SoundOutcome.playedHabit);
    });
  });

  group('Perfect Day', () {
    test('replaces the habit sound: one sound, not two', () async {
      expect(
        await complete('last', perfect: true),
        SoundOutcome.playedPerfectDay,
      );
      expect(player.sounds, [CompletionSound.perfectDay]);
    });

    test('at most once per Arc and date; a redone Perfect Day plays the '
        'habit sound', () async {
      await complete('last', perfect: true);
      clock.advance(const Duration(seconds: 4));
      expect(await complete('last', perfect: true), SoundOutcome.playedHabit);
      clock.advance(const Duration(seconds: 4));
      expect(
        await complete('last', perfect: true, date: today.addDays(1)),
        SoundOutcome.playedPerfectDay,
      );
      clock.advance(const Duration(seconds: 4));
      expect(
        await complete('last', perfect: true, arc: 2),
        SoundOutcome.playedPerfectDay,
        reason: 'a restarted Arc is another Arc',
      );
      expect(player.sounds, [
        CompletionSound.perfectDay,
        CompletionSound.habit,
        CompletionSound.perfectDay,
        CompletionSound.perfectDay,
      ]);
    });

    test('a throttled Perfect Day is not counted as played', () async {
      await complete('a');
      clock.advance(const Duration(milliseconds: 100));
      expect(
        await complete('b', perfect: true),
        SoundOutcome.throttledGlobally,
      );
      clock.advance(const Duration(seconds: 4));
      expect(await complete('b', perfect: true), SoundOutcome.playedPerfectDay);
    });
  });

  group('never late, never in the way', () {
    test('a save slower than 1 s stays silent', () async {
      final tapped = clock.now;
      clock.advance(const Duration(milliseconds: 1001));
      expect(await complete('water', requestedAt: tapped), SoundOutcome.late);
      expect(player.plays, isEmpty);
    });

    test('an unreadable setting plays nothing and throws nothing', () async {
      preferences.failLoad = true;
      expect(await complete('water'), SoundOutcome.unavailable);
      expect(
        await feedback.preview(SoundTheme.iceCrystal),
        SoundOutcome.unavailable,
      );
      await feedback.warmUp();
      expect(player.plays, isEmpty);
    });

    test('a failing or missing player never surfaces an error', () async {
      player
        ..failPlay = true
        ..failPrepare = true;
      await feedback.warmUp();
      expect(await complete('water'), SoundOutcome.playedHabit);
      await Future<void>.delayed(Duration.zero);
      clock.advance(const Duration(seconds: 1));
      expect(
        await feedback.preview(SoundTheme.warmEmber),
        SoundOutcome.playedHabit,
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('a hung player never holds up the caller', () async {
      player.hang = true;
      final outcome = await complete('water')
          .timeout(const Duration(seconds: 1));
      expect(outcome, SoundOutcome.playedHabit);
    });
  });

  test('warm-up loads the sounds only while they are on', () async {
    await feedback.warmUp();
    expect(player.prepares, 1);
    preferences.value = const FeedbackPreferences(
      soundsEnabled: false,
      soundTheme: SoundTheme.iceCrystal,
    );
    await feedback.warmUp();
    expect(player.prepares, 1);
  });

  test('a preview plays the habit sound of the set asked for, and shares '
      'the global throttle', () async {
    expect(
      await feedback.preview(SoundTheme.summitSpark),
      SoundOutcome.playedHabit,
    );
    expect(player.plays, [(SoundTheme.summitSpark, CompletionSound.habit)]);
    clock.advance(const Duration(milliseconds: 200));
    expect(
      await feedback.preview(SoundTheme.warmEmber),
      SoundOutcome.throttledGlobally,
    );
    expect(await complete('water'), SoundOutcome.throttledGlobally);
  });

  test('the providers: a wall-clock rollback cannot reopen a throttle '
      'window, and a restore (new epoch) keeps the throttle', () async {
    final wall = FakeClock(DateTime(2026, 11, 23, 21));
    final db = memoryDatabase();
    addTearDown(db.close);
    final monotonic = FakeMonotonic();
    final fake = FakeSoundPlayer();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(wall),
        monotonicClockProvider.overrideWithValue(monotonic.call),
        soundPlayerProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    Future<SoundOutcome> done(String habit) => container
        .read(completionFeedbackProvider)
        .habitCompleted(
          sessionId: 1,
          date: today,
          habitId: habit,
          perfectDay: false,
          requestedAt: monotonic.now,
        );

    expect(await done('water'), SoundOutcome.playedHabit);
    wall.current = DateTime(2026, 11, 23, 19); // the phone's clock goes back
    monotonic.advance(const Duration(milliseconds: 100));
    expect(await done('water'), SoundOutcome.throttledForHabit);
    expect(await done('reading'), SoundOutcome.throttledGlobally);

    final engine = container.read(completionFeedbackProvider);
    container.read(appEpochProvider.notifier).restart();
    expect(
      identical(container.read(completionFeedbackProvider), engine),
      isTrue,
    );
    expect(fake.plays, hasLength(1));
  });
}
