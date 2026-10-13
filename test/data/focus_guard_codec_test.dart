import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/data/focus_guard_codec.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';

void main() {
  group('FocusGuardCodec.usageAccess', () {
    test('reads the three states and fails closed on anything else', () {
      expect(FocusGuardCodec.usageAccess('granted'), UsageAccess.granted);
      expect(FocusGuardCodec.usageAccess('notGranted'), UsageAccess.notGranted);
      expect(
        FocusGuardCodec.usageAccess('unsupported'),
        UsageAccess.unsupported,
      );
      for (final raw in <Object?>[null, '', 'GRANTED', true, 1, const {}]) {
        expect(FocusGuardCodec.usageAccess(raw), UsageAccess.notGranted);
      }
    });
  });

  group('FocusGuardCodec.launchableApps', () {
    test('reads package name and label maps', () {
      expect(
        FocusGuardCodec.launchableApps([
          {'packageName': 'com.example.alpha', 'label': 'Alpha'},
          {'packageName': 'com.example.bravo'},
        ]),
        const [
          LaunchableAppCandidate(
            packageName: 'com.example.alpha',
            label: 'Alpha',
          ),
          LaunchableAppCandidate(packageName: 'com.example.bravo', label: ''),
        ],
      );
    });

    test('skips malformed entries; a non-list is empty', () {
      expect(
        FocusGuardCodec.launchableApps([
          null,
          'com.example.alpha',
          {'label': 'No package'},
          {'packageName': ''},
          {'packageName': 7, 'label': 'Number'},
          {'packageName': 'com.example.ok', 'label': 3},
        ]),
        const [
          LaunchableAppCandidate(packageName: 'com.example.ok', label: ''),
        ],
      );
      expect(FocusGuardCodec.launchableApps(null), isEmpty);
      expect(FocusGuardCodec.launchableApps(const {}), isEmpty);
      expect(FocusGuardCodec.launchableApps(const []), isEmpty);
    });
  });

  group('FocusGuardCodec.foregroundTime', () {
    const requested = {'com.example.alpha', 'com.example.bravo'};

    test('reads milliseconds for the requested packages only', () {
      expect(
        FocusGuardCodec.foregroundTime({
          'com.example.alpha': 90000,
          'com.example.bravo': 0,
          'com.example.other': 5000,
        }, requested),
        {
          'com.example.alpha': const Duration(seconds: 90),
          'com.example.bravo': Duration.zero,
        },
      );
    });

    test('skips values that are not non-negative integers', () {
      expect(
        FocusGuardCodec.foregroundTime({
          'com.example.alpha': -1,
          'com.example.bravo': 1.5,
          7: 1000,
        }, requested),
        isEmpty,
      );
      expect(FocusGuardCodec.foregroundTime(const {}, requested), isEmpty);
    });

    test('a non-map is an error, never zero', () {
      for (final raw in <Object?>[null, const [], 'x', 0]) {
        expect(
          () => FocusGuardCodec.foregroundTime(raw, requested),
          throwsFormatException,
        );
      }
    });
  });
}
