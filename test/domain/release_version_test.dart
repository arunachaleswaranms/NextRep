import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/update/release_version.dart';

ReleaseVersion _v(String text) => ReleaseVersion.tryParse(text)!;

void main() {
  group('comparison is numeric, never by string', () {
    for (final (newer, older) in [
      ('1.2.0', '1.1.0'),
      ('1.10.0', '1.9.9'),
      ('1.2.1', '1.2.0'),
      ('2.0.0', '1.99.99'),
      ('1.0.10', '1.0.9'),
      ('10.0.0', '9.0.0'),
      ('0.0.1', '0.0.0'),
    ]) {
      test('$newer > $older', () {
        expect(_v(newer) > _v(older), isTrue);
        expect(_v(older) < _v(newer), isTrue);
        expect(_v(newer).compareTo(_v(older)), greaterThan(0));
        expect(_v(older).compareTo(_v(newer)), lessThan(0));
      });
    }

    test('1.2.0 == 1.2.0', () {
      expect(_v('1.2.0'), _v('1.2.0'));
      expect(_v('1.2.0').compareTo(_v('1.2.0')), 0);
      expect(_v('1.2.0') > _v('1.2.0'), isFalse);
      expect(_v('1.2.0') < _v('1.2.0'), isFalse);
      expect(_v('1.2.0').hashCode, _v('1.2.0').hashCode);
    });

    test('1.1.0 < 1.2.0', () {
      expect(_v('1.1.0') < _v('1.2.0'), isTrue);
    });

    test('sorting orders by number', () {
      final sorted = [
        '1.9.9',
        '1.10.0',
        '1.2.0',
        '2.0.0',
        '1.99.99',
      ].map(_v).toList()..sort();
      expect(sorted.map((v) => '$v'), [
        '1.2.0',
        '1.9.9',
        '1.10.0',
        '1.99.99',
        '2.0.0',
      ]);
    });
  });

  group('stable tags', () {
    for (final tag in ['v1.0.0', 'v1.1.0', 'v1.2.0', 'v2.0.0', 'v0.0.0']) {
      test('$tag parses and round-trips', () {
        final version = ReleaseVersion.tryParseTag(tag);
        expect(version, isNotNull);
        expect(version!.tag, tag);
      });
    }

    test('the largest accepted part is six digits', () {
      expect(ReleaseVersion.tryParseTag('v999999.999999.999999'), isNotNull);
      expect(ReleaseVersion.tryParseTag('v1000000.0.0'), isNull);
    });
  });

  group('malformed tags are rejected, never guessed', () {
    for (final tag in [
      '',
      'v',
      'v1',
      'v1.2',
      '1.2',
      '1.2.0', // a tag needs its v
      'V1.2.0',
      'vv1.2.0',
      ' v1.2.0',
      'v1.2.0 ',
      'v1.2.0\n',
      'v1.2.0-beta',
      'v1.2.0-rc.1',
      'v1.2.0+3',
      'v1.2.0.0',
      'v1..0',
      'v1.2.',
      'v.1.2',
      'v1,2,0',
      'v1-2-0',
      'v1_2_0',
      'v1.2/0',
      'v-1.2.0',
      'v1.-2.0',
      'v+1.2.0',
      'v01.2.0',
      'v1.02.0',
      'v1.2.00',
      'v1.2.x',
      'v1.2.0a',
      'v１.２.０', // full-width digits
      'v0x1.2.0',
      'v1e3.0.0',
      'v99999999999999999999999.0.0',
      'v1.2.${'9' * 400}',
      'v${'1.' * 200}0',
    ]) {
      test('"${tag.length > 30 ? '${tag.substring(0, 30)}…' : tag}"', () {
        expect(ReleaseVersion.tryParseTag(tag), isNull);
      });
    }
  });

  group('installed version names', () {
    test('a plain version parses', () {
      expect(ReleaseVersion.tryParse('1.1.0'), const ReleaseVersion(1, 1, 0));
    });

    test('anything else does not', () {
      for (final name in ['v1.1.0', '1.1', '1.1.0+2', '1.1.0-dev', '']) {
        expect(ReleaseVersion.tryParse(name), isNull, reason: name);
      }
    });
  });
}
