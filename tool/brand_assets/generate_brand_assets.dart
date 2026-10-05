// Generates every NextRep brand asset from the one geometry below: the
// vector source (SVG), the Android adaptive / monochrome / notification
// vector drawables, and the PNG launcher, App Store, Play Store and launch
// images.
//
// Dev-time only. It is not a test and is not run by `flutter test` (which
// only looks in test/). Run it from the repository root after changing the
// geometry, then review the diff:
//
//   flutter test tool/brand_assets/generate_brand_assets.dart
//
// Flutter's own renderer rasterises the PNGs, so no image tool or package
// is needed.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Geometry, on the 108 × 108 Android adaptive-icon canvas.
//
// Launchers show at most the central 72 × 72 (18..90) and may mask down to
// a circle of radius 33 around the centre, so the peaks and the summit
// light stay inside that circle. The snowfield runs off the bottom and the
// sides on purpose, like a horizon, so every mask cuts it cleanly.
// ---------------------------------------------------------------------------

const _canvas = 108.0;

/// The visible square of the adaptive canvas (what iOS and legacy Android
/// icons show).
const _visible = Rect.fromLTRB(18, 18, 90, 90);

// Palette: the app's WinterColors tokens (lib/app/theme/winter_tokens.dart).
const _skyTop = Color(0xFF04070F); // skyTop
const _skyHorizon = Color(0xFF1C365E); // skyHorizon
const _background = Color(0xFF070B18); // background
const _snowTop = Color(0xFFF2F6FF); // textPrimary
const _snowBase = Color(0xFFB9CDEE); // between snow and fog
const _shade = Color(0xFF0E1A33); // backgroundTop, used translucent
const _summit = Color(0xFFFFB45C); // warmLight

/// Two peaks and a saddle: an ascent that reads as a quiet "N".
const _massif = <Offset>[
  Offset(-2, 110),
  Offset(-2, 80),
  Offset(18, 73),
  Offset(30, 63),
  Offset(41, 54),
  Offset(50, 63),
  Offset(62, 41),
  Offset(73, 56),
  Offset(81, 61),
  Offset(93, 68),
  Offset(110, 75),
  Offset(110, 110),
];

/// The shadowed faces east of each ridge line.
const _mainShadow = <Offset>[
  Offset(62, 41),
  Offset(73, 56),
  Offset(81, 61),
  Offset(93, 68),
  Offset(110, 75),
  Offset(110, 110),
  Offset(74, 110),
  Offset(65, 62),
];
const _leftShadow = <Offset>[
  Offset(41, 54),
  Offset(50, 63),
  Offset(47, 69),
  Offset(42, 64),
];

const _summitLight = Offset(62, 32);
const _summitRadius = 3.2;
const _summitHalo = 9.0;

/// A few cold stars in the background sky.
const _stars = <(Offset, double)>[
  (Offset(33, 36), 0.85),
  (Offset(44, 27), 0.6),
  (Offset(80, 34), 0.75),
];

/// The notification glyph: the same ridge as a closed silhouette, on
/// Android's 24 × 24 status-bar grid.
const _glyphRidge = <Offset>[
  Offset(20, 76),
  Offset(41, 54),
  Offset(50, 63),
  Offset(62, 41),
  Offset(73, 56),
  Offset(81, 61),
  Offset(96, 70),
  Offset(96, 76),
];

// ---------------------------------------------------------------------------
// Vector output
// ---------------------------------------------------------------------------

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _polygonPath(List<Offset> points, {Offset shift = Offset.zero}) {
  final b = StringBuffer();
  for (var i = 0; i < points.length; i++) {
    final p = points[i] + shift;
    b.write('${i == 0 ? 'M' : 'L'}${_n(p.dx)},${_n(p.dy)} ');
  }
  return '${b.toString().trim()} Z';
}

String _circlePath(Offset c, double r, {Offset shift = Offset.zero}) {
  final x = c.dx + shift.dx;
  final y = c.dy + shift.dy;
  return 'M${_n(x - r)},${_n(y)} '
      'A${_n(r)},${_n(r)} 0 1,0 ${_n(x + r)},${_n(y)} '
      'A${_n(r)},${_n(r)} 0 1,0 ${_n(x - r)},${_n(y)} Z';
}

String _hex(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

String _argb(Color c, [double opacity = 1]) {
  final a = (c.a * opacity * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${a.toUpperCase()}${_hex(c)}';
}

const _xmlHeader = '<?xml version="1.0" encoding="utf-8"?>\n';
const _generated =
    '<!-- Output of tool/brand_assets/generate_brand_assets.dart: change '
    'the geometry there, not here. -->\n';

String _svg() {
  final v = _visible;
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${_n(_canvas)} ${_n(_canvas)}" width="1080" height="1080">
  <!-- NextRep app icon, source of truth: the full 108 x 108 adaptive-icon
       canvas. Launchers show the central square ${_n(v.left)}..${_n(v.right)}.
       Output of tool/brand_assets/generate_brand_assets.dart. -->
  <defs>
    <linearGradient id="sky" x1="0" y1="${_n(v.top)}" x2="0" y2="${_n(v.bottom)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#${_hex(_skyTop)}"/>
      <stop offset="1" stop-color="#${_hex(_skyHorizon)}"/>
    </linearGradient>
    <radialGradient id="glow" cx="${_n(_summitLight.dx)}" cy="${_n(_summitLight.dy)}" r="${_n(_summitHalo)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#${_hex(_summit)}" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#${_hex(_summit)}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="snow" x1="0" y1="41" x2="0" y2="90" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#${_hex(_snowTop)}"/>
      <stop offset="1" stop-color="#${_hex(_snowBase)}"/>
    </linearGradient>
  </defs>
  <rect width="${_n(_canvas)}" height="${_n(_canvas)}" fill="url(#sky)"/>
${_stars.map((s) => '  <path d="${_circlePath(s.$1, s.$2)}" fill="#${_hex(_snowTop)}" fill-opacity="0.7"/>').join('\n')}
  <path d="${_polygonPath(_massif)}" fill="url(#snow)"/>
  <path d="${_polygonPath(_mainShadow)}" fill="#${_hex(_shade)}" fill-opacity="0.32"/>
  <path d="${_polygonPath(_leftShadow)}" fill="#${_hex(_shade)}" fill-opacity="0.26"/>
  <path d="${_circlePath(_summitLight, _summitHalo)}" fill="url(#glow)"/>
  <path d="${_circlePath(_summitLight, _summitRadius)}" fill="#${_hex(_summit)}"/>
</svg>
''';
}

String _vector({
  required double size,
  required double viewport,
  required String body,
  bool aapt = false,
}) =>
    '$_xmlHeader$_generated'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"'
    '${aapt ? '\n    xmlns:aapt="http://schemas.android.com/aapt"' : ''}\n'
    '    android:width="${_n(size)}dp"\n'
    '    android:height="${_n(size)}dp"\n'
    '    android:viewportWidth="${_n(viewport)}"\n'
    '    android:viewportHeight="${_n(viewport)}">\n'
    '$body'
    '</vector>\n';

String _gradientPath(String d, Color start, Color end, double y1, double y2) =>
    '''
    <path android:pathData="$d">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="0"
                android:startY="${_n(y1)}"
                android:endX="0"
                android:endY="${_n(y2)}"
                android:startColor="${_argb(start)}"
                android:endColor="${_argb(end)}" />
        </aapt:attr>
    </path>
''';

/// The soft warm glow around the summit light.
String _glowPath() =>
    '''
    <path android:pathData="${_circlePath(_summitLight, _summitHalo)}">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="radial"
                android:centerX="${_n(_summitLight.dx)}"
                android:centerY="${_n(_summitLight.dy)}"
                android:gradientRadius="${_n(_summitHalo)}"
                android:startColor="${_argb(_summit, 0.55)}"
                android:endColor="${_argb(_summit, 0)}" />
        </aapt:attr>
    </path>
''';

String _solidPath(String d, Color color, [double opacity = 1]) =>
    '    <path\n'
    '        android:fillColor="${_argb(color, opacity)}"\n'
    '        android:pathData="$d" />\n';

String _adaptiveBackground() => _vector(
  size: _canvas,
  viewport: _canvas,
  aapt: true,
  body: [
    _gradientPath(
      'M0,0 L${_n(_canvas)},0 L${_n(_canvas)},${_n(_canvas)} L0,${_n(_canvas)} Z',
      _skyTop,
      _skyHorizon,
      _visible.top,
      _visible.bottom,
    ),
    for (final (c, r) in _stars) _solidPath(_circlePath(c, r), _snowTop, 0.7),
  ].join(),
);

String _adaptiveForeground() => _vector(
  size: _canvas,
  viewport: _canvas,
  aapt: true,
  body: [
    _gradientPath(_polygonPath(_massif), _snowTop, _snowBase, 41, 90),
    _solidPath(_polygonPath(_mainShadow), _shade, 0.32),
    _solidPath(_polygonPath(_leftShadow), _shade, 0.26),
    _glowPath(),
    _solidPath(_circlePath(_summitLight, _summitRadius), _summit),
  ].join(),
);

/// Android 13+ themed icon: one tinted silhouette, alpha only.
String _adaptiveMonochrome() => _vector(
  size: _canvas,
  viewport: _canvas,
  body: [
    _solidPath(_polygonPath(_massif), const Color(0xFFFFFFFF)),
    _solidPath(
      _circlePath(_summitLight, _summitRadius),
      const Color(0xFFFFFFFF),
    ),
  ].join(),
);

/// Status-bar icon: white on transparent, as Android requires.
String _notificationGlyph() {
  // Fit the ridge and the summit light into the 24 grid with 1.5 of
  // padding.
  const minX = 20.0, maxX = 96.0;
  final minY = _summitLight.dy - _summitRadius, maxY = 76.0;
  final scale = 21 / math.max(maxX - minX, maxY - minY);
  final dx = (24 - (maxX - minX) * scale) / 2;
  final dy = (24 - (maxY - minY) * scale) / 2;
  Offset map(Offset p) =>
      Offset((p.dx - minX) * scale + dx, (p.dy - minY) * scale + dy);
  return _vector(
    size: 24,
    viewport: 24,
    body: [
      _solidPath(
        _polygonPath([for (final p in _glyphRidge) map(p)]),
        const Color(0xFFFFFFFF),
      ),
      _solidPath(
        _circlePath(map(_summitLight), _summitRadius * scale),
        const Color(0xFFFFFFFF),
      ),
    ].join(),
  );
}

// ---------------------------------------------------------------------------
// Raster output
// ---------------------------------------------------------------------------

ui.Path _polygon(List<Offset> points) => ui.Path()..addPolygon(points, true);

/// Paints the icon's adaptive canvas region [region] into a [size] square.
void _paintIcon(ui.Canvas canvas, double size, {Rect region = _visible}) {
  final s = size / region.width;
  canvas
    ..save()
    ..scale(s)
    ..translate(-region.left, -region.top);
  final sky = ui.Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, _visible.top),
      Offset(0, _visible.bottom),
      [_skyTop, _skyHorizon],
    );
  canvas.drawRect(const Rect.fromLTWH(0, 0, _canvas, _canvas), sky);
  for (final (c, r) in _stars) {
    canvas.drawCircle(c, r, ui.Paint()..color = _snowTop.withValues(alpha: .7));
  }
  canvas
    ..drawPath(
      _polygon(_massif),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 41),
          const Offset(0, 90),
          [_snowTop, _snowBase],
        ),
    )
    ..drawPath(
      _polygon(_mainShadow),
      ui.Paint()..color = _shade.withValues(alpha: .32),
    )
    ..drawPath(
      _polygon(_leftShadow),
      ui.Paint()..color = _shade.withValues(alpha: .26),
    )
    ..drawCircle(
      _summitLight,
      _summitHalo,
      ui.Paint()
        ..shader = ui.Gradient.radial(_summitLight, _summitHalo, [
          _summit.withValues(alpha: .55),
          _summit.withValues(alpha: 0),
        ]),
    )
    ..drawCircle(_summitLight, _summitRadius, ui.Paint()..color = _summit)
    ..restore();
}

typedef _Painter = void Function(ui.Canvas canvas, double size);

/// Renders [paint] into a [size] PNG at [path]. With [opaque] the file is
/// written as RGB without an alpha channel, which the App Store requires
/// of app icons (Flutter's own encoder always writes RGBA).
Future<void> _png(
  String path,
  int size,
  _Painter paint, {
  bool opaque = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas, size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final Uint8List bytes;
  if (opaque) {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = _rgbPng(rgba!.buffer.asUint8List(), size, size);
  } else {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = png!.buffer.asUint8List();
  }
  (File(path)..parent.createSync(recursive: true)).writeAsBytesSync(bytes);
  image.dispose();
}

/// A minimal PNG encoder for 8-bit RGB (colour type 2): drops the alpha
/// of [rgba], which must be fully opaque.
Uint8List _rgbPng(Uint8List rgba, int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] != 255) {
        throw StateError('Opaque PNG has a transparent pixel at $x,$y');
      }
      raw.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // colour type: RGB
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes())))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typed = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(typed));
  return Uint8List.fromList([
    ...length.buffer.asUint8List(),
    ...typed,
    ...crc.buffer.asUint8List(),
  ]);
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Opaque full square: iOS masks it itself and rejects alpha.
void _square(ui.Canvas c, double size) => _paintIcon(c, size);

/// Legacy Android (API 24–25) launcher: a rounded square on transparent.
void _rounded(ui.Canvas c, double size) {
  final inset = size * 0.04;
  final rect = Rect.fromLTWH(inset, inset, size - 2 * inset, size - 2 * inset);
  c
    ..save()
    ..clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(size * 0.18)))
    ..translate(inset, inset);
  _paintIcon(c, rect.width);
  c.restore();
}

/// Legacy Android round launcher.
void _round(ui.Canvas c, double size) {
  final inset = size * 0.04;
  c
    ..save()
    ..clipPath(
      ui.Path()..addOval(
        Rect.fromLTWH(inset, inset, size - 2 * inset, size - 2 * inset),
      ),
    )
    ..translate(inset, inset);
  _paintIcon(c, size - 2 * inset);
  c.restore();
}

/// Launch mark: the rounded icon floating on the app background colour.
void _launch(ui.Canvas c, double size) {
  c.drawRect(Rect.fromLTWH(0, 0, size, size), ui.Paint()..color = _background);
  _rounded(c, size);
}

// ---------------------------------------------------------------------------

void main() {
  testWidgets('generate NextRep brand assets', (tester) async {
    await tester.runAsync(() async {
      void write(String path, String content) => (File(
        path,
      )..parent.createSync(recursive: true)).writeAsStringSync(content);

      // Vector sources.
      write('assets/branding/nextrep_icon.svg', _svg());
      const res = 'android/app/src/main/res';
      write('$res/drawable/ic_launcher_background.xml', _adaptiveBackground());
      write('$res/drawable/ic_launcher_foreground.xml', _adaptiveForeground());
      write('$res/drawable/ic_launcher_monochrome.xml', _adaptiveMonochrome());
      write('$res/drawable/ic_stat_reminder.xml', _notificationGlyph());
      const adaptive =
          '$_xmlHeader$_generated'
          '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <background android:drawable="@drawable/ic_launcher_background" />\n'
          '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
          '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
          '</adaptive-icon>\n';
      write('$res/mipmap-anydpi-v26/ic_launcher.xml', adaptive);
      write('$res/mipmap-anydpi-v26/ic_launcher_round.xml', adaptive);

      // Legacy Android launcher PNGs (48 dp).
      const densities = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      for (final MapEntry(key: density, value: px) in densities.entries) {
        await _png('$res/mipmap-$density/ic_launcher.png', px, _rounded);
        await _png('$res/mipmap-$density/ic_launcher_round.png', px, _round);
      }

      // iOS app icons (every size in AppIcon.appiconset/Contents.json).
      const ios = 'ios/Runner/Assets.xcassets';
      const iosSizes = {
        '20x20@1x': 20,
        '20x20@2x': 40,
        '20x20@3x': 60,
        '29x29@1x': 29,
        '29x29@2x': 58,
        '29x29@3x': 87,
        '40x40@1x': 40,
        '40x40@2x': 80,
        '40x40@3x': 120,
        '60x60@2x': 120,
        '60x60@3x': 180,
        '76x76@1x': 76,
        '76x76@2x': 152,
        '83.5x83.5@2x': 167,
        '1024x1024@1x': 1024,
      };
      for (final MapEntry(key: name, value: px) in iosSizes.entries) {
        await _png(
          '$ios/AppIcon.appiconset/Icon-App-$name.png',
          px,
          _square,
          opaque: true,
        );
      }

      // iOS launch screen mark (120 pt).
      for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
        await _png(
          '$ios/LaunchImage.imageset/LaunchImage$suffix.png',
          120 * scale,
          _launch,
          opaque: true,
        );
      }

      // Store listing icons and a large preview for review.
      for (final (name, px) in [
        ('play_store_icon_512', 512),
        ('app_store_icon_1024', 1024),
      ]) {
        await _png(
          'assets/branding/store/$name.png',
          px,
          _square,
          opaque: true,
        );
      }
    });
  });
}
