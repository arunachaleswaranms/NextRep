import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Turns a rendered share card into its PNG.
///
/// Cards are laid out on a fixed [canvas] of logical pixels and exported at
/// a fixed [pixelRatio], so every image is exactly [pixelWidth] x
/// [pixelHeight] (4:5 portrait), whatever the phone's width, density or
/// text size. Only the card's own [RenderRepaintBoundary] is drawn: no
/// preview controls, app bars or navigation.
abstract final class ShareCardCapture {
  /// The card's design canvas, in logical pixels.
  static const Size canvas = Size(360, 450);

  /// Export scale: 360 x 450 → 1080 x 1350.
  static const double pixelRatio = 3;

  static const int pixelWidth = 1080;
  static const int pixelHeight = 1350;

  /// The PNG of [boundary], which must wrap a card of exactly [canvas].
  /// The bytes stay in memory; nothing is written or logged here.
  static Future<Uint8List> png(RenderRepaintBoundary boundary) async {
    assert(boundary.size == canvas, 'a share card is ${canvas.toString()}');
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
