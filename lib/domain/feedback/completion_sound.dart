import 'feedback_preferences.dart';

/// The two sounds of every set (ARC_CONTROL_SPEC § 8.3).
enum CompletionSound {
  /// A habit became complete.
  habit,

  /// The completion that made today a Perfect Day. Plays instead of
  /// [habit], never after it.
  perfectDay;

  /// The bundled file (`pubspec.yaml` assets) of [sound] in [theme]. The
  /// native players look it up by this key; it is never downloaded.
  static String assetFor(SoundTheme theme, CompletionSound sound) =>
      'assets/sounds/${_fileStem[theme]}_${_fileSuffix[sound]}.wav';

  /// How long [sound] in [theme] plays: the file's exact length, from
  /// `tool/sounds/generate_completion_sounds.dart`. The feedback engine
  /// lets nothing else start until it is over, so sounds never overlap.
  static Duration lengthOf(SoundTheme theme, CompletionSound sound) =>
      switch ((theme, sound)) {
        (_, CompletionSound.perfectDay) => const Duration(milliseconds: 900),
        (SoundTheme.iceCrystal, _) => const Duration(milliseconds: 350),
        (SoundTheme.summitSpark, _) => const Duration(milliseconds: 450),
        (SoundTheme.warmEmber, _) => const Duration(milliseconds: 400),
      };

  /// The channel id of [sound] in [theme] (`iceCrystal.habit`), which the
  /// native players map to [assetFor].
  static String idOf(SoundTheme theme, CompletionSound sound) =>
      '${theme.name}.${sound.name}';

  static const _fileStem = {
    SoundTheme.iceCrystal: 'ice_crystal',
    SoundTheme.summitSpark: 'summit_spark',
    SoundTheme.warmEmber: 'warm_ember',
  };

  static const _fileSuffix = {
    CompletionSound.habit: 'habit',
    CompletionSound.perfectDay: 'perfect_day',
  };
}

/// Plays the bundled completion sounds (Android `SoundPool`, iOS
/// `AVAudioPlayer`; see `lib/data/native_sound_player.dart`).
///
/// Only the feedback engine calls it. Every call is fire-and-forget: a
/// player that isn't ready, is unavailable or fails simply plays nothing,
/// and never delays or undoes what triggered it. The platform decides
/// whether anything is heard (silent, vibrate, Do Not Disturb, volume).
abstract interface class SoundPlayer {
  /// Loads the sounds, so the first one can play at once. Repeatable.
  Future<void> prepare();

  /// Plays [sound] of [theme] once, now, or not at all.
  Future<void> play(SoundTheme theme, CompletionSound sound);
}

/// A player that plays nothing: tests, and platforms without a native
/// player.
final class SilentSoundPlayer implements SoundPlayer {
  const SilentSoundPlayer();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> play(SoundTheme theme, CompletionSound sound) async {}
}
