import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/feedback/completion_feedback.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';

import '../support/fakes.dart';
import '../support/sound_app.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// Sound feedback is feedback only (spec § 8.5; prompt § 10): the same
/// Today session leaves exactly the same stored data (progress, XP, Perfect
/// Day, streaks, achievements, modes, Arc) whether sounds are on, off, the
/// player fails or hangs on every call, or every sound is still waiting for
/// its setting when Today goes away and is dropped (G-R1).
Future<Map<String, List<Map<String, Object?>>>> _everyTableBut(
  AppDatabase db,
  String excluded,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      if (t.read<String>('name') != excluded)
        t.read<String>('name'): [
          for (final row
              in await db
                  .customSelect(
                    'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                  )
                  .get())
            row.data,
        ],
  };
}

enum _Run { soundsOn, soundsOff, playerFails, playerHangs, cancelled }

void main() {
  Future<Map<String, List<Map<String, Object?>>>> session(
    WidgetTester tester,
    _Run run,
  ) async {
    await phoneSize(tester);
    // The starter habits (fixed ids): Workout 30 min, Water 8 glasses,
    // Learning 20 min, No Junk Food.
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 4, 9)));
    addTearDown(app.db.close);
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
    if (run == _Run.soundsOff) {
      await DriftFeedbackPreferencesRepository(app.db).save(
        const FeedbackPreferences(
          soundsEnabled: false,
          soundTheme: SoundTheme.iceCrystal,
        ),
        at: app.clock.now(),
      );
    }
    final player = FakeSoundPlayer()
      ..failPlay = run == _Run.playerFails
      ..failPrepare = run == _Run.playerFails
      ..hang = run == _Run.playerHangs;
    final monotonic = FakeMonotonic();
    // Cancelled: every setting read waits until Today is gone.
    final held = HeldFeedbackPreferences(
      DriftFeedbackPreferencesRepository(app.db),
    )..holding = run == _Run.cancelled;
    await tester.pumpWidget(
      soundApp(
        app,
        player: player,
        monotonic: monotonic,
        extra: [
          completionFeedbackProvider.overrideWithValue(
            CompletionFeedback(
              preferences: held,
              player: player,
              elapsed: monotonic.call,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String tooltip, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        // Cancelled: the clock stands still, so every held request is
        // dropped by its cancelled origin, not by the 1 s latency rule.
        if (run != _Run.cancelled) {
          monotonic.advance(const Duration(seconds: 4));
        }
        await tapTooltip(tester, tooltip);
      }
    }

    // A Perfect Day, an undo that revokes it, and the redo; a decrement
    // and the step back; level and achievement celebrations on the way.
    await tap('Complete No Junk Food');
    await tap('Add to Water Intake', 8);
    await tap('Add to Workout', 6);
    await tap('Add to Learning / Skills', 4);
    await tap('Undo No Junk Food');
    await tap('Complete No Junk Food');
    await tap('Decrease Water Intake');
    await tap('Add to Water Intake');
    await clearCelebrations(tester);
    final today = await app.tracking.today();
    expect(today.completion.completed, 4);
    expect(today.perfectDays.streak.current, 1);
    expect(tester.takeException(), isNull);
    if (run == _Run.soundsOff || run == _Run.cancelled) {
      expect(player.plays, isEmpty);
    } else {
      expect(player.plays, isNotEmpty);
    }
    if (run == _Run.cancelled) {
      expect(held.waitingLoads, greaterThan(4));
      // Today goes; only then does the setting arrive: nothing plays.
      await tester.pumpWidget(const SizedBox());
      held.release();
      await tester.pump();
      expect(held.returned, greaterThan(4));
      expect(player.plays, isEmpty);
    }
    await shutDown(tester);
    // A hung player's call never returns; let its timer go.
    if (run == _Run.playerHangs) await tester.pump(const Duration(days: 2));
    return _everyTableBut(app.db, 'feedback_preferences');
  }

  testWidgets('sounds on, sounds off, a failing or hung player and '
      'dropped (cancelled) sounds store exactly the same data', (tester) async {
    final on = await session(tester, _Run.soundsOn);
    final off = await session(tester, _Run.soundsOff);
    final failing = await session(tester, _Run.playerFails);
    final hung = await session(tester, _Run.playerHangs);
    final cancelled = await session(tester, _Run.cancelled);
    expect(on['xp_transactions'], isNotEmpty);
    expect(on['achievement_unlocks'], isNotEmpty);
    expect(off, on);
    expect(failing, on);
    expect(hung, on);
    expect(cancelled, on);
  });
}
