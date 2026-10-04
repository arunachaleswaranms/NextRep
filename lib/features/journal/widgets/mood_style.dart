import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/reflection/daily_reflection.dart';

/// How a mood looks. Every mood has its own label and icon, so the colour is
/// never the only cue. A rough day gets the warm recovery colour rather than
/// an alarm red: no shame for a hard day.
extension MoodStyle on Mood {
  String get label => switch (this) {
    Mood.rough => 'Rough',
    Mood.okay => 'Okay',
    Mood.good => 'Good',
    Mood.excellent => 'Excellent',
  };

  IconData get icon => switch (this) {
    Mood.rough => Icons.sentiment_dissatisfied_rounded,
    Mood.okay => Icons.sentiment_neutral_rounded,
    Mood.good => Icons.sentiment_satisfied_rounded,
    Mood.excellent => Icons.sentiment_very_satisfied_rounded,
  };

  Color colorOf(WinterColors colors) => switch (this) {
    Mood.rough => colors.recovery,
    Mood.okay => colors.textSecondary,
    Mood.good => colors.accentSecondary,
    Mood.excellent => colors.celebration,
  };
}
