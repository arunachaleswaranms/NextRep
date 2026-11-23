import 'dart:async';
import 'dart:math' as math;

import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/local_date.dart';
import 'completion_sound.dart';
import 'feedback_preferences.dart';

/// Time since an arbitrary fixed point that only moves forward: never the
/// wall clock, so changing the phone's date or time can't reopen a
/// throttle window.
typedef MonotonicClock = Duration Function();

final _processWatch = Stopwatch()..start();

/// The app process's monotonic clock.
Duration processElapsed() => _processWatch.elapsed;

/// What became of one request for a sound.
enum SoundOutcome {
  /// [CompletionSound.habit] was handed to the player.
  playedHabit,

  /// [CompletionSound.perfectDay] was handed to the player.
  playedPerfectDay,

  /// Completion sounds are off: the player wasn't asked.
  disabled,

  /// Another sound started less than [CompletionFeedback.globalGap] ago,
  /// or is still playing. Dropped, never queued.
  throttledGlobally,

  /// This habit sounded less than [CompletionFeedback.habitGap] ago.
  /// Dropped, never queued.
  throttledForHabit,

  /// The save took longer than [CompletionFeedback.maxLatency]: too late
  /// to belong to the tap. Dropped.
  late,

  /// The setting couldn't be read. Nothing plays; the action is unaffected.
  unavailable;

  bool get played => this == playedHabit || this == playedPerfectDay;
}

/// Completion sounds (ARC_CONTROL_SPEC § 8, addendum AD15): decides
/// whether a saved completion sounds, and which sound, then hands it to the
/// [SoundPlayer] without waiting.
///
/// Feedback only. It reads the setting and its own in-memory throttle; it
/// never writes, never awards anything and is never awaited by the action
/// it follows. Its state is the throttle alone, kept for the app process:
///
/// * one sound at a time across the app, at most one per [globalGap], and
///   none while the previous one is still playing (no overlap)
/// * at most one per habit per [habitGap]
/// * the Perfect Day sound at most once per Arc and date
///
/// A throttled sound is dropped. Nothing is queued or retried, so nothing
/// plays late. Throttle times come from a [MonotonicClock], so a wall-clock
/// change can't bypass it.
final class CompletionFeedback {
  CompletionFeedback({
    required this._preferences,
    required this._player,
    required this._elapsed,
  });

  static const globalGap = Duration(milliseconds: 500);
  static const habitGap = Duration(seconds: 3);

  /// The longest a sound may follow the tap that caused it. A save slower
  /// than this (a busy queue) stays silent rather than sounding late.
  static const maxLatency = Duration(seconds: 1);

  final FeedbackPreferencesRepository _preferences;
  final SoundPlayer _player;
  final MonotonicClock _elapsed;

  /// No sound may start before this.
  Duration? _quietUntil;

  /// When each habit (`session/habit`) last sounded.
  final _habitSounded = <String, Duration>{};

  /// Arc and date (`session/date`) whose Perfect Day sound has played.
  final _perfectDaysSounded = <String>{};

  /// The current monotonic time, for [habitCompleted]'s `requestedAt`.
  Duration now() => _elapsed();

  /// Loads the sounds if they are on, so the first completion can play at
  /// once. Never throws.
  Future<void> warmUp() async {
    try {
      if ((await _preferences.load()).soundsEnabled) await _player.prepare();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  /// A saved commit made [habitId] complete on [date] of Arc [sessionId]
  /// (its ledger granted the habit's award). [perfectDay]: the same commit
  /// granted the day's Perfect Day bonus. [requestedAt] is [now] when the
  /// user acted.
  ///
  /// Plays the Perfect Day sound instead of the habit sound the first time
  /// a date of an Arc becomes perfect; afterwards (a Perfect Day undone and
  /// redone) the habit sound, like any restored completion.
  Future<SoundOutcome> habitCompleted({
    required int sessionId,
    required LocalDate date,
    required String habitId,
    required bool perfectDay,
    required Duration requestedAt,
  }) async {
    final FeedbackPreferences preferences;
    try {
      preferences = await _preferences.load();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      return SoundOutcome.unavailable;
    }
    // From here to the end runs without yielding, so two completions can't
    // both pass the throttle.
    if (!preferences.soundsEnabled) return SoundOutcome.disabled;
    final now = _elapsed();
    if (now - requestedAt > maxLatency) return SoundOutcome.late;

    final dayKey = '$sessionId/$date';
    final sound = perfectDay && !_perfectDaysSounded.contains(dayKey)
        ? CompletionSound.perfectDay
        : CompletionSound.habit;
    final habitKey = '$sessionId/$habitId';
    final last = _habitSounded[habitKey];
    if (last != null && now - last < habitGap) {
      return SoundOutcome.throttledForHabit;
    }
    if (!_start(preferences.soundTheme, sound, now)) {
      return SoundOutcome.throttledGlobally;
    }
    _habitSounded
      ..removeWhere((_, at) => now - at >= habitGap)
      ..[habitKey] = now;
    if (sound == CompletionSound.perfectDay) _perfectDaysSounded.add(dayKey);
    return sound == CompletionSound.perfectDay
        ? SoundOutcome.playedPerfectDay
        : SoundOutcome.playedHabit;
  }

  /// The settings screen's preview: [theme]'s habit sound, if sounds are
  /// on and nothing is playing. Never throws.
  Future<SoundOutcome> preview(SoundTheme theme) async {
    final FeedbackPreferences preferences;
    try {
      preferences = await _preferences.load();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      return SoundOutcome.unavailable;
    }
    if (!preferences.soundsEnabled) return SoundOutcome.disabled;
    // A preview is the first sound a user may hear: make sure it's loaded.
    // Not awaited: if loading isn't finished, this preview stays silent.
    unawaited(_guard(_player.prepare));
    return _start(theme, CompletionSound.habit, _elapsed())
        ? SoundOutcome.playedHabit
        : SoundOutcome.throttledGlobally;
  }

  /// Starts [sound] unless another is playing or started within
  /// [globalGap]. The player isn't awaited: its result changes nothing.
  bool _start(SoundTheme theme, CompletionSound sound, Duration now) {
    final quiet = _quietUntil;
    if (quiet != null && now < quiet) return false;
    final length = CompletionSound.lengthOf(theme, sound);
    _quietUntil =
        now +
        Duration(
          microseconds: math.max(
            globalGap.inMicroseconds,
            length.inMicroseconds,
          ),
        );
    unawaited(_guard(() => _player.play(theme, sound)));
    return true;
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  static void _report(Object error, StackTrace stackTrace) =>
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'sound');
}
