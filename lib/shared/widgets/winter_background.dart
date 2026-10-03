import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Full-screen night-sky gradient. The future cinematic scene (mountains,
/// snow, aurora) replaces this widget's decoration, not individual screens.
class WinterBackground extends StatelessWidget {
  const WinterBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.backgroundTop, colors.background],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
