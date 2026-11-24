import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static boundaries of the completion sounds (Phase 12G, spec § 8.5, N6;
/// addendum AD14 / AD15). What a device makes audible is qualified on the
/// emulator (docs/PHASE_12G.md); this checks the source can't drift from
/// the approved design.
Map<String, String> _sources(String root, String extension) => {
  for (final file in Directory(root).listSync(recursive: true))
    if (file is File && file.path.endsWith(extension))
      file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
};

Set<String> _filesMatching(Map<String, String> sources, Pattern pattern) => {
  for (final MapEntry(:key, :value) in sources.entries)
    if (value.contains(pattern)) key,
};

void main() {
  final dart = _sources('lib', '.dart');
  final kotlin = _sources('android/app/src/main/kotlin', '.kt');
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  const soundKotlin =
      'android/app/src/main/kotlin/com/nextrep/nextrep/sound/CompletionSoundChannel.kt';

  test('every method channel has its own name; sound and Focus Guard '
      'never share one', () {
    final pattern = RegExp(r"""['"](com\.nextrep\.nextrep/[a-z_]+)['"]""");
    final dartNames = {
      for (final source in dart.values)
        for (final m in pattern.allMatches(source)) m.group(1)!,
    };
    final kotlinNames = {
      for (final source in kotlin.values)
        for (final m in pattern.allMatches(source)) m.group(1)!,
    };
    expect(dartNames, {
      'com.nextrep.nextrep/focus_guard',
      'com.nextrep.nextrep/completion_sound',
    });
    expect(kotlinNames, dartNames);
    expect(swift, contains('"com.nextrep.nextrep/completion_sound"'));
  });

  test('Android: SoundPool on the sonification stream, one stream, no '
      'audio focus, no other player', () {
    final source = kotlin[soundKotlin]!;
    expect(source, contains('SoundPool.Builder()'));
    expect(source, contains('.setMaxStreams(1)'));
    expect(source, contains('AudioAttributes.USAGE_ASSISTANCE_SONIFICATION'));
    expect(source, contains('AudioAttributes.CONTENT_TYPE_SONIFICATION'));
    for (final api in [
      'requestAudioFocus',
      'AudioFocusRequest',
      'MediaPlayer',
      'AudioTrack',
      'Ringtone',
      'USAGE_MEDIA',
      'USAGE_ALARM',
      'USAGE_NOTIFICATION',
      'STREAM_MUSIC',
      'setStreamVolume',
      'adjustStreamVolume',
    ]) {
      expect(_filesMatching(kotlin, api), isEmpty, reason: api);
    }
    // Only the sound player touches audio at all.
    expect(_filesMatching(kotlin, 'android.media.'), {
      soundKotlin,
      'android/app/src/main/kotlin/com/nextrep/nextrep/sound/CompletionSounds.kt',
    });
  });

  test('Android: no notification channel, permission or network for sound', () {
    for (final path in [
      soundKotlin,
      'android/app/src/main/kotlin/com/nextrep/nextrep/sound/CompletionSounds.kt',
    ]) {
      final source = kotlin[path]!;
      for (final api in [
        'NotificationChannel',
        'createNotificationChannel',
        'requestPermissions',
        'checkSelfPermission',
        'java.net',
        'Uri.parse',
        'http',
      ]) {
        expect(source.contains(api), isFalse, reason: '$path uses $api');
      }
    }
    // The manifest is untouched by Phase 12G: the CI permission audit pins
    // the release APK's exact permission set.
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest.contains('MODIFY_AUDIO_SETTINGS'), isFalse);
    expect(manifest.contains('ACCESS_NOTIFICATION_POLICY'), isFalse);
  });

  test('iOS: AVAudioPlayer in the ambient session (silent switch, mixes)', () {
    expect(swift, contains('AVAudioPlayer'));
    expect(swift, contains('setCategory(.ambient'));
    for (final api in [
      '.playback',
      '.playAndRecord',
      '.soloAmbient',
      'URLSession',
    ]) {
      expect(swift.contains(api), isFalse, reason: api);
    }
    // The generated plugin registration is kept.
    expect(swift, contains('GeneratedPluginRegistrant.register('));
  });

  test('Dart: only the feedback engine plays, only the sound settings and '
      'Today ask it to', () {
    // Only the engine calls the player; only the composition root and the
    // engine know it.
    expect(_filesMatching(dart, '_player.play('), {
      'lib/domain/feedback/completion_feedback.dart',
    });
    expect(_filesMatching(dart, RegExp(r'\bSoundPlayer\b')), {
      'lib/domain/feedback/completion_sound.dart',
      'lib/domain/feedback/completion_feedback.dart',
      'lib/data/native_sound_player.dart',
      'lib/app/dependencies.dart',
    });
    expect(_filesMatching(dart, 'completionSoundChannel'), {
      'lib/data/native_sound_player.dart',
    });
    // Completions sound from Today's saved commit only; previews from the
    // settings screen only.
    expect(_filesMatching(dart, 'feedback.habitCompleted('), {
      'lib/features/today/today_screen.dart',
    });
    expect(_filesMatching(dart, 'completionFeedbackProvider).preview('), {
      'lib/features/sound/sound_settings_screen.dart',
    });
    // G-R1: every request carries its screen's origin, and only the
    // eligibility scope creates an active one, so no screen can sound
    // without being the one shown. Both sounding screens use the scope.
    expect(_filesMatching(dart, RegExp(r'(=>?|\(|,)\s*SoundOrigin\(\)')), {
      'lib/features/sound/sound_origin_scope.dart',
    });
    expect(_filesMatching(dart, 'with SoundOriginScope'), {
      'lib/features/today/today_screen.dart',
      'lib/features/sound/sound_settings_screen.dart',
    });
    expect(
      _filesMatching(dart, 'overrideWithValue(const NativeSoundPlayer())'),
      {'lib/main.dart'},
    );
    // Feedback never writes or awards: no repository save, ledger or XP.
    final engine = dart['lib/domain/feedback/completion_feedback.dart']!;
    for (final api in [
      '.save(',
      'XpAward',
      'Ledger',
      'achievement',
      'commitDay',
    ]) {
      expect(engine.contains(api), isFalse, reason: api);
    }
  });

  test('sounds are bundled, never fetched', () {
    final sound = {
      for (final p in [
        'lib/domain/feedback/completion_sound.dart',
        'lib/domain/feedback/completion_feedback.dart',
        'lib/data/native_sound_player.dart',
      ])
        p: File(p).readAsStringSync(),
    };
    for (final MapEntry(:key, :value) in sound.entries) {
      for (final api in [
        'http',
        'Uri.parse',
        'NetworkAssetBundle',
        'HttpClient',
      ]) {
        expect(value.contains(api), isFalse, reason: '$key uses $api');
      }
    }
  });
}
