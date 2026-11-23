// Generates NextRep's six completion sounds (Phase 12G) from the recipes
// below: three sets, each with a habit sound and a Perfect Day sound.
//
// Every sample is computed here from sine partials and envelopes. No
// recording, sample, sound library or third-party melody is used, and the
// script needs nothing but the Dart SDK. The output is 16-bit PCM WAV,
// mono, 16 kHz: the one format both Android's SoundPool and iOS's
// AVAudioPlayer decode without an encoder (whose output would vary by
// platform and version) and without priming silence.
//
// Dev-time only, not a test. From the repository root:
//
//   dart run tool/sounds/generate_completion_sounds.dart          # write
//   dart run tool/sounds/generate_completion_sounds.dart --check  # verify
//
// `--check` regenerates in memory and compares with the committed files:
// headers byte for byte, samples within 1 LSB (libm's last-bit differences
// between platforms can move a rounded sample by one step). CI runs it.
//
// The sounds are original to NextRep and released with the repository
// under the MIT license (LICENSE).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Output sample rate. 16 kHz keeps all six files near 125 KB in total.
const sampleRate = 16000;

/// Partials above this are left out, well below Nyquist (8 kHz).
const maxPartialHz = 7000.0;

/// Peak level of every file: −5 dBFS, a few dB of headroom.
const peakDbfs = -5.0;

/// Raised-cosine fade at the start of every note (no click).
const attackSeconds = 0.006;

/// Raised-cosine fade over the end of every file, reaching exactly zero.
const releaseSeconds = 0.045;

const outputDirectory = 'assets/sounds';

/// One sine partial of a note: [ratio] × the note's frequency, [gain]
/// relative to the fundamental, decaying with time constant [decay]
/// seconds.
final class Partial {
  const Partial(this.ratio, this.gain, this.decay);

  final double ratio;
  final double gain;
  final double decay;
}

/// A note of [frequency] Hz starting at [onset] seconds, [gain] relative
/// to the loudest note, with the set's timbre scaled by [decayScale].
final class Note {
  const Note(this.onset, this.frequency, {this.gain = 1, this.decayScale = 1});

  final double onset;
  final double frequency;
  final double gain;
  final double decayScale;
}

/// One output file.
final class Recipe {
  const Recipe({
    required this.file,
    required this.seconds,
    required this.timbre,
    required this.notes,
  });

  final String file;
  final double seconds;
  final List<Partial> timbre;
  final List<Note> notes;
}

double hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

// Ice Crystal: bright and glassy. Two soft partials (the fundamental and
// an inharmonic 2.76× partial, as in a struck glass bar) and a faintly
// detuned copy of the fundamental for shimmer.
const iceTimbre = [
  Partial(1, 1, 0.11),
  Partial(1.004, 0.28, 0.13),
  Partial(2.76, 0.30, 0.045),
];

// Summit Spark: a plucked string. Harmonics 1–6 at 1/n, the higher ones
// dying away faster.
final sparkTimbre = [
  for (var n = 1; n <= 6; n++)
    Partial(n.toDouble(), 1 / n, 0.16 / math.pow(n, 0.8)),
];

// Warm Ember: a soft mallet on a wooden bar. The bar's 1 : 4 : 10
// partials, a little second harmonic for warmth on small speakers, and a
// quick high partial for the mallet's contact.
const emberTimbre = [
  Partial(1, 1, 0.14),
  Partial(2, 0.22, 0.08),
  Partial(4, 0.12, 0.035),
  Partial(10, 0.025, 0.008),
];

final recipes = [
  Recipe(
    file: 'ice_crystal_habit.wav',
    seconds: 0.35,
    timbre: iceTimbre,
    notes: [Note(0, hz(93))], // A6
  ),
  Recipe(
    file: 'ice_crystal_perfect_day.wav',
    seconds: 0.90,
    timbre: iceTimbre,
    // A rising A-major figure: A5, C#6, E6, the last ringing longer.
    notes: [
      Note(0, hz(81), gain: 0.8),
      Note(0.15, hz(85), gain: 0.85),
      Note(0.30, hz(88), decayScale: 2.4),
    ],
  ),
  Recipe(
    file: 'summit_spark_habit.wav',
    seconds: 0.45,
    timbre: sparkTimbre,
    // A quick rising fifth: D5 to A5.
    notes: [Note(0, hz(74), gain: 0.75), Note(0.11, hz(81))],
  ),
  Recipe(
    file: 'summit_spark_perfect_day.wav',
    seconds: 0.90,
    timbre: sparkTimbre,
    // The fifth, continued up the D-major chord: D5, A5, D6, F#6.
    notes: [
      Note(0, hz(74), gain: 0.7),
      Note(0.10, hz(81), gain: 0.8),
      Note(0.20, hz(86), gain: 0.9),
      Note(0.30, hz(90), decayScale: 2),
    ],
  ),
  Recipe(
    file: 'warm_ember_habit.wav',
    seconds: 0.40,
    timbre: emberTimbre,
    notes: [Note(0, hz(67))], // G4
  ),
  Recipe(
    file: 'warm_ember_perfect_day.wav',
    seconds: 0.90,
    timbre: emberTimbre,
    // Gently up the G-major chord: G4, B4, D5, then a soft G5.
    notes: [
      Note(0, hz(67), gain: 0.85),
      Note(0.14, hz(71), gain: 0.85),
      Note(0.28, hz(74), gain: 0.9, decayScale: 1.6),
      Note(0.42, hz(79), gain: 0.55, decayScale: 2.2),
    ],
  ),
];

/// The recipe's samples as doubles, peak-normalised to [peakDbfs], with
/// the attack and release fades applied.
List<double> render(Recipe recipe) {
  final length = (recipe.seconds * sampleRate).round();
  final out = List<double>.filled(length, 0);
  final attack = (attackSeconds * sampleRate).round();
  for (final note in recipe.notes) {
    final start = (note.onset * sampleRate).round();
    for (final partial in recipe.timbre) {
      final frequency = note.frequency * partial.ratio;
      // Band-limited: a high note simply has fewer partials (no aliasing).
      if (frequency > maxPartialHz) continue;
      final omega = 2 * math.pi * frequency / sampleRate;
      final decay = partial.decay * note.decayScale;
      for (var i = start; i < length; i++) {
        final t = (i - start) / sampleRate;
        final k = i - start;
        final rise = k < attack
            ? 0.5 - 0.5 * math.cos(math.pi * k / attack)
            : 1;
        out[i] +=
            note.gain *
            partial.gain *
            rise *
            math.exp(-t / decay) *
            math.sin(omega * k);
      }
    }
  }
  // The file's release: a raised-cosine fade to exactly zero.
  final release = (releaseSeconds * sampleRate).round();
  for (var k = 0; k < release; k++) {
    final i = length - release + k;
    out[i] *= 0.5 + 0.5 * math.cos(math.pi * (k + 1) / release);
  }
  final peak = out.fold<double>(0, (m, s) => math.max(m, s.abs()));
  final target = math.pow(10, peakDbfs / 20);
  return [for (final s in out) s / peak * target];
}

/// 16-bit little-endian PCM samples.
Int16List quantise(List<double> samples) => Int16List.fromList([
  for (final s in samples) (s * 32767).round().clamp(-32768, 32767),
]);

/// A canonical 44-byte RIFF/WAVE header plus [pcm].
Uint8List wav(Int16List pcm) {
  final data = pcm.lengthInBytes;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + data, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, data, Endian.little);
  final bytes = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(pcm.buffer.asUint8List(pcm.offsetInBytes, data));
  return bytes.takeBytes();
}

void main(List<String> args) {
  final check = args.contains('--check');
  var failures = 0;
  var total = 0;
  for (final recipe in recipes) {
    final bytes = wav(quantise(render(recipe)));
    final file = File('$outputDirectory/${recipe.file}');
    total += bytes.length;
    if (!check) {
      file
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      stdout.writeln('wrote ${file.path} (${bytes.length} bytes)');
      continue;
    }
    final problem = _compare(file, bytes);
    if (problem == null) {
      stdout.writeln('ok    ${file.path}');
    } else {
      failures++;
      stderr.writeln('FAIL  ${file.path}: $problem');
    }
  }
  stdout.writeln('total ${recipes.length} files, $total bytes');
  if (failures > 0) exit(1);
}

/// Why [file] doesn't match [expected], or null when it does.
String? _compare(File file, Uint8List expected) {
  if (!file.existsSync()) return 'missing';
  final actual = file.readAsBytesSync();
  if (actual.length != expected.length) {
    return 'length ${actual.length}, expected ${expected.length}';
  }
  for (var i = 0; i < 44; i++) {
    if (actual[i] != expected[i]) return 'header differs at byte $i';
  }
  final a = ByteData.sublistView(actual);
  final e = ByteData.sublistView(expected);
  for (var i = 44; i < actual.length; i += 2) {
    final diff = a.getInt16(i, Endian.little) - e.getInt16(i, Endian.little);
    if (diff.abs() > 1) return 'sample ${(i - 44) ~/ 2} differs by $diff';
  }
  return null;
}
