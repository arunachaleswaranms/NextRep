import 'package:flutter/services.dart';

import '../domain/feedback/completion_sound.dart';
import '../domain/feedback/feedback_preferences.dart';

/// The native completion-sound players: `CompletionSoundChannel.kt`
/// (Android, `SoundPool`, sonification audio attributes) and
/// `AppDelegate.swift` (iOS, `AVAudioPlayer`, ambient session). Its own
/// channel, separate from Focus Guard's.
const completionSoundChannel = MethodChannel(
  'com.nextrep.nextrep/completion_sound',
);

/// [SoundPlayer] over [completionSoundChannel]. Created in `main.dart` on
/// Android and iOS only.
///
/// The native side owns every device rule: it plays only bundled files,
/// never asks for audio focus (music keeps playing), and stays silent when
/// the phone is silenced, on vibrate or in Do Not Disturb, or while the
/// sounds are still loading. Its answer is informational; callers ignore
/// it.
final class NativeSoundPlayer implements SoundPlayer {
  const NativeSoundPlayer();

  /// Every sound's id and bundled asset, for `prepare`.
  static Map<String, String> get catalogue => {
    for (final theme in SoundTheme.values)
      for (final sound in CompletionSound.values)
        CompletionSound.idOf(theme, sound): CompletionSound.assetFor(
          theme,
          sound,
        ),
  };

  @override
  Future<void> prepare() => completionSoundChannel.invokeMethod<Object?>(
    'prepare',
    {'sounds': catalogue},
  );

  @override
  Future<void> play(SoundTheme theme, CompletionSound sound) =>
      completionSoundChannel.invokeMethod<Object?>('play', {
        'sound': CompletionSound.idOf(theme, sound),
      });
}
