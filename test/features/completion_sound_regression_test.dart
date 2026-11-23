import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';

import '../support/fakes.dart';
import '../support/sound_app.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// Sound feedback is feedback only (spec § 8.5; prompt § 10): the same
/// Today session leaves exactly the same stored data (progress, XP, Perfect
/// Day, streaks, achievements, modes, Arc) whether sounds are on, off, or
/// the player fails on every call.
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

enum _Run { soundsOn, soundsOff, playerFails }

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
      ..failPrepare = run == _Run.playerFails;
    final monotonic = FakeMonotonic();
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String tooltip, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        monotonic.advance(const Duration(seconds: 4));
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
    if (run == _Run.soundsOff) {
      expect(player.plays, isEmpty);
    } else {
      expect(player.plays, isNotEmpty);
    }
    await shutDown(tester);
    return _everyTableBut(app.db, 'feedback_preferences');
  }

  testWidgets('sounds on, sounds off and a failing player store exactly the '
      'same data', (tester) async {
    final on = await session(tester, _Run.soundsOn);
    final off = await session(tester, _Run.soundsOff);
    final failing = await session(tester, _Run.playerFails);
    expect(on['xp_transactions'], isNotEmpty);
    expect(on['achievement_unlocks'], isNotEmpty);
    expect(off, on);
    expect(failing, on);
  });
}
