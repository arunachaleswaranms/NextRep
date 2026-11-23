import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';

/// Records what the app asked the native player to do. Deterministic:
/// whether anything would be heard is a device question (emulator
/// qualification), not this fake's.
final class FakeSoundPlayer implements SoundPlayer {
  final plays = <(SoundTheme, CompletionSound)>[];
  int prepares = 0;

  /// Makes play / prepare throw, like a missing native side.
  bool failPlay = false;
  bool failPrepare = false;

  /// While set, play never completes (a hung platform channel).
  bool hang = false;

  List<CompletionSound> get sounds => [for (final (_, s) in plays) s];

  @override
  Future<void> prepare() async {
    prepares++;
    if (failPrepare) throw StateError('no native player');
  }

  @override
  Future<void> play(SoundTheme theme, CompletionSound sound) async {
    plays.add((theme, sound));
    if (failPlay) throw StateError('playback failed');
    if (hang) await Future<void>.delayed(const Duration(days: 1));
  }
}

/// [FeedbackPreferencesRepository] in memory, which can fail.
final class FakeFeedbackPreferences implements FeedbackPreferencesRepository {
  FakeFeedbackPreferences([this.value = FeedbackPreferences.defaults]);

  FeedbackPreferences value;
  bool failLoad = false;
  bool failSave = false;
  int loads = 0;
  int saves = 0;

  @override
  Future<FeedbackPreferences> load() async {
    loads++;
    if (failLoad) throw StateError('read failed');
    return value;
  }

  @override
  Future<void> save(
    FeedbackPreferences preferences, {
    required DateTime at,
  }) async {
    if (failSave) throw StateError('write failed');
    saves++;
    value = preferences;
  }
}

/// A monotonic clock a test moves by hand.
final class FakeMonotonic {
  Duration now = const Duration(hours: 1);

  Duration call() => now;

  void advance(Duration by) => now += by;
}
