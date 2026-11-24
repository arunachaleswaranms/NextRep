import 'dart:async';

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

/// Wraps [inner] so a test decides when each read or write returns
/// (G-R1 races). While [holding], every [load] / [save] waits on its own
/// [Completer] until [release]; a released [load] then reads [inner], so it
/// returns what is stored at that moment. Nothing depends on real time.
final class HeldFeedbackPreferences implements FeedbackPreferencesRepository {
  HeldFeedbackPreferences(this.inner);

  final FeedbackPreferencesRepository inner;

  /// Holds the next loads; [holdSaves] the next saves.
  bool holding = false;
  bool holdSaves = false;

  /// Runs in the same microtask a released [load] returns its value: the
  /// last moment before the caller resumes after its `await`.
  void Function()? beforeReturn;

  final _loads = <Completer<void>>[];
  final _saves = <Completer<void>>[];

  /// Loads waiting for [release].
  int get waitingLoads => _loads.length;

  /// Loads that have returned their value to the caller.
  int returned = 0;

  /// Saves waiting for [releaseSaves].
  int get waitingSaves => _saves.length;

  @override
  Future<FeedbackPreferences> load() async {
    if (holding) {
      final gate = Completer<void>();
      _loads.add(gate);
      await gate.future;
    }
    final value = await inner.load();
    beforeReturn?.call();
    returned++;
    return value;
  }

  @override
  Future<void> save(
    FeedbackPreferences preferences, {
    required DateTime at,
  }) async {
    if (holdSaves) {
      final gate = Completer<void>();
      _saves.add(gate);
      await gate.future;
    }
    await inner.save(preferences, at: at);
  }

  /// Lets every held load go (and stops holding new ones).
  void release() {
    holding = false;
    for (final gate in _loads) {
      gate.complete();
    }
    _loads.clear();
  }

  /// Lets every held save go (and stops holding new ones).
  void releaseSaves() {
    holdSaves = false;
    for (final gate in _saves) {
      gate.complete();
    }
    _saves.clear();
  }
}

/// A monotonic clock a test moves by hand.
final class FakeMonotonic {
  Duration now = const Duration(hours: 1);

  Duration call() => now;

  void advance(Duration by) => now += by;
}
