import 'package:characters/characters.dart';

import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';

/// How a day felt. [key] is persisted, so never change an existing key; add
/// new values instead. Display text lives in the UI.
enum Mood {
  rough('rough'),
  okay('okay'),
  good('good'),
  excellent('excellent');

  const Mood(this.key);

  /// Stable storage key.
  final String key;

  /// The mood stored as [key], or null for an unknown key (e.g. one written
  /// by a newer version, or a corrupted value).
  static Mood? fromKey(String? key) {
    for (final mood in values) {
      if (mood.key == key) return mood;
    }
    return null;
  }
}

/// A short nightly check-in for one challenge date of one arc. There is at
/// most one per session and date.
///
/// Private, local-only data: it is never logged, uploaded or included in
/// error reports.
final class DailyReflection {
  const DailyReflection({
    required this.sessionId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.mood,
    this.win,
    this.improvement,
  });

  final int sessionId;

  /// The challenge date reflected on. Its day number is derived from the
  /// arc's start date, never stored.
  final LocalDate date;
  final Mood? mood;

  /// "One win today". Trimmed; null when left empty.
  final String? win;

  /// "One thing to improve". Trimmed; null when left empty.
  final String? improvement;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// What the user entered, before validation.
final class ReflectionDraft {
  const ReflectionDraft({this.mood, this.win = '', this.improvement = ''});

  final Mood? mood;
  final String win;
  final String improvement;
}

/// A validated draft: trimmed, within limits and not empty.
final class ReflectionContent {
  const ReflectionContent._({this.mood, this.win, this.improvement});

  final Mood? mood;
  final String? win;
  final String? improvement;
}

abstract final class ReflectionRules {
  /// Longest "win" or "improvement" answer, in characters, after trimming.
  static const int maxTextLength = 240;

  /// Validates [draft]: answers are trimmed (an answer of only whitespace
  /// counts as empty), each is at most [maxTextLength] characters, and a
  /// reflection needs a mood or at least one answer.
  static ReflectionContent validate(ReflectionDraft draft) {
    final win = _clean(draft.win);
    final improvement = _clean(draft.improvement);
    if (draft.mood == null && win == null && improvement == null) {
      throw const DomainFailure(
        DomainRule.reflectionEmpty,
        'A reflection needs a mood or some text',
      );
    }
    return ReflectionContent._(
      mood: draft.mood,
      win: win,
      improvement: improvement,
    );
  }

  static String? _clean(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    // Count user-perceived characters (grapheme clusters), as a text
    // field's length limit does, so an emoji counts once.
    if (trimmed.characters.length > maxTextLength) {
      // The message is for developers; it never includes the text itself.
      throw const DomainFailure(
        DomainRule.reflectionTooLong,
        'A reflection answer is over the length limit',
      );
    }
    return trimmed;
  }
}
