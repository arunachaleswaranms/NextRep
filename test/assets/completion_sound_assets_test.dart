import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';

/// The six bundled completion sounds (Phase 12G, ARC_CONTROL_SPEC § 8.3):
/// what the native players are given, checked from the committed bytes.
///
/// Whether they sound right is the owner's Gate G listening review, not
/// this test.
final class _Wav {
  _Wav(this.path, Uint8List bytes) : data = ByteData.sublistView(bytes) {
    size = bytes.length;
  }

  final String path;
  final ByteData data;
  late final int size;

  String tag(int offset) =>
      String.fromCharCodes(data.buffer.asUint8List(offset, 4));
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);

  int get channels => u16(22);
  int get sampleRate => u32(24);
  int get bitsPerSample => u16(34);

  List<int> get samples => [
    for (var i = 44; i < size; i += 2) data.getInt16(i, Endian.little),
  ];

  Duration get duration =>
      Duration(microseconds: (samples.length * 1000000 / sampleRate).round());
}

double _dbfs(num amplitude) =>
    amplitude == 0 ? -200 : 20 * math.log(amplitude / 32768) / math.ln10;

void main() {
  final files = {
    for (final theme in SoundTheme.values)
      for (final sound in CompletionSound.values)
        (theme, sound): CompletionSound.assetFor(theme, sound),
  };
  _Wav read(String asset) => _Wav(asset, File(asset).readAsBytesSync());

  test('six files, one per set and sound, all declared in pubspec', () {
    expect(files, hasLength(6));
    expect(files.values.toSet(), hasLength(6));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('    - assets/sounds/'));
    final onDisk = Directory('assets/sounds')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.wav'))
        .toSet();
    expect(onDisk, files.values.toSet(), reason: 'no stray or missing file');
  });

  test('together well under 200 KB', () {
    final total = files.values.fold<int>(0, (sum, a) => sum + read(a).size);
    expect(total, lessThan(150 * 1024));
  });

  for (final MapEntry(key: (theme, sound), value: asset) in files.entries) {
    group(asset, () {
      late _Wav wav;
      late List<int> samples;
      setUpAll(() {
        wav = read(asset);
        samples = wav.samples;
      });

      test('16-bit PCM WAV, mono, 16 kHz, canonical header', () {
        expect(wav.tag(0), 'RIFF');
        expect(wav.u32(4), wav.size - 8);
        expect(wav.tag(8), 'WAVE');
        expect(wav.tag(12), 'fmt ');
        expect(wav.u16(20), 1, reason: 'PCM');
        expect(wav.channels, 1);
        expect(wav.sampleRate, 16000);
        expect(wav.bitsPerSample, 16);
        expect(wav.tag(36), 'data');
        expect(wav.u32(40), wav.size - 44);
      });

      test('the length the spec describes, under 1 second', () {
        expect(wav.duration, CompletionSound.lengthOf(theme, sound));
        expect(wav.duration, lessThan(const Duration(seconds: 1)));
        final ms = wav.duration.inMilliseconds;
        switch ((theme, sound)) {
          case (_, CompletionSound.perfectDay):
            expect(ms, inInclusiveRange(800, 950));
          case (SoundTheme.iceCrystal, _):
            expect(ms, inInclusiveRange(300, 400));
          case (SoundTheme.summitSpark, _):
            expect(ms, inInclusiveRange(400, 500));
          case (SoundTheme.warmEmber, _):
            expect(ms, inInclusiveRange(350, 450));
        }
      });

      test('peak −5 dBFS: headroom, no clipping', () {
        final peak = samples.fold<int>(0, (m, s) => math.max(m, s.abs()));
        expect(_dbfs(peak), closeTo(-5, 0.1));
        expect(samples.where((s) => s.abs() >= 32767), isEmpty);
      });

      test('starts and ends at zero, with fades (no click)', () {
        expect(samples.first, 0);
        expect(samples.last, 0);
        // The first and last 1 ms stay far below the −5 dBFS peak: the
        // sound fades in and out rather than starting or stopping abruptly.
        const edge = 16;
        for (final s in [
          ...samples.take(edge),
          ...samples.skip(samples.length - edge),
        ]) {
          expect(_dbfs(s.abs()), lessThan(-25));
        }
        // No step anywhere jumps like a discontinuity would.
        var jump = 0;
        for (var i = 1; i < samples.length; i++) {
          jump = math.max(jump, (samples[i] - samples[i - 1]).abs());
        }
        expect(_dbfs(jump), lessThan(-3));
      });

      test('no silent padding at either end', () {
        // Audible (above −40 dBFS) within the first 10 ms ...
        final first = samples.indexWhere((s) => _dbfs(s.abs()) > -40);
        expect(first, inInclusiveRange(0, 160));
        // ... and still sounding (above −60 dBFS) in the last 60 ms.
        final last = samples.lastIndexWhere((s) => _dbfs(s.abs()) > -60);
        expect(samples.length - last, lessThan(960));
      });

      test('no DC offset', () {
        final mean = samples.fold<int>(0, (a, s) => a + s) / samples.length;
        expect(mean.abs(), lessThan(40));
      });
    });
  }
}
