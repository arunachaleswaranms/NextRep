/// The completion-sound set. Persisted by [name] (schema v7, backup format
/// 4), so never rename values.
///
/// Stored and restored since Phase 12E1; played since Phase 12G
/// (`CompletionFeedback`, `assets/sounds/`, Sound & Feedback).
enum SoundTheme {
  /// The default set.
  iceCrystal,
  summitSpark,
  warmEmber;

  /// The value persisted as [name], or null for anything else.
  static SoundTheme? fromName(String name) {
    for (final theme in values) {
      if (theme.name == name) return theme;
    }
    return null;
  }
}

/// App-level feedback settings (schema v7, `feedback_preferences`). They
/// belong to the app, not to an Arc.
final class FeedbackPreferences {
  const FeedbackPreferences({
    required this.soundsEnabled,
    required this.soundTheme,
  });

  /// What a device reads while nothing is stored: sounds on, Ice Crystal
  /// (addendum AD15, ARC_CONTROL_SPEC § 8.4). Reading never stores it.
  static const defaults = FeedbackPreferences(
    soundsEnabled: true,
    soundTheme: SoundTheme.iceCrystal,
  );

  final bool soundsEnabled;
  final SoundTheme soundTheme;

  @override
  bool operator ==(Object other) =>
      other is FeedbackPreferences &&
      other.soundsEnabled == soundsEnabled &&
      other.soundTheme == soundTheme;

  @override
  int get hashCode => Object.hash(soundsEnabled, soundTheme);

  @override
  String toString() =>
      'FeedbackPreferences(soundsEnabled: $soundsEnabled, '
      'soundTheme: ${soundTheme.name})';
}

/// Persistence of [FeedbackPreferences]: the single row of
/// `feedback_preferences`, absent until the settings are first changed.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class FeedbackPreferencesRepository {
  /// The stored settings, or [FeedbackPreferences.defaults] when no row
  /// exists. Never writes.
  Future<FeedbackPreferences> load();

  /// Stores [preferences] as the single row, stamped [at].
  Future<void> save(FeedbackPreferences preferences, {required DateTime at});
}
