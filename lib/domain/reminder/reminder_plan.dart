import '../../core/time/local_date.dart';
import '../winter_arc/winter_arc_session.dart';
import 'reminder_preferences.dart';

/// The two reminder types. [payload] is what a tapped notification hands
/// back to the app, so never change an existing payload.
enum ReminderKind {
  /// Opens Today.
  daily('today', 100),

  /// Opens today's reflection in the Journal.
  reflection('journal', 200);

  const ReminderKind(this.payload, this._idBase);

  final String payload;
  final int _idBase;

  /// The kind a notification [payload] belongs to, or null if unknown.
  static ReminderKind? fromPayload(String? payload) {
    for (final kind in values) {
      if (kind.payload == payload) return kind;
    }
    return null;
  }
}

/// One notification to show at [at] (local wall-clock time).
final class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable within a plan; unique across kinds.
  final int id;
  final ReminderKind kind;
  final DateTime at;
  final String title;

  /// Generic copy only: a reminder never contains reflection text or any
  /// other personal entry.
  final String body;

  String get payload => kind.payload;

  @override
  String toString() => 'PlannedReminder(${kind.name}, $at)';
}

/// Pure planning of which reminders should be pending right now.
///
/// Reminders are one-shot notifications for concrete arc days, computed
/// from the local wall clock, rather than an OS-level "every day at 08:00"
/// repeat. That way they never outlive the arc (nothing is planned after
/// its last day or without an active arc), each one can name its day, and
/// a time-zone or daylight-saving change is picked up on the next
/// reconciliation. The app reconciles on launch, on resume, and whenever
/// the preferences or the arc change.
abstract final class ReminderPlanner {
  /// How many days ahead reminders are planned. Opening the app at least
  /// once in that window keeps them going; after that they pause on their
  /// own instead of nagging someone who has stepped away.
  static const int horizonDays = 14;

  /// The reminders that should be pending at [now] for [preferences], given
  /// the [active] arc (null when no arc is running).
  static List<PlannedReminder> plan({
    required ReminderPreferences preferences,
    required WinterArcSession? active,
    required DateTime now,
  }) {
    if (active == null || active.status != WinterArcStatus.active) {
      return const [];
    }
    final today = LocalDate.fromDateTime(now);
    return [
      if (preferences.dailyEnabled)
        ..._forKind(
          ReminderKind.daily,
          preferences.dailyTime,
          active,
          today,
          now,
        ),
      if (preferences.reflectionEnabled)
        ..._forKind(
          ReminderKind.reflection,
          preferences.reflectionTime,
          active,
          today,
          now,
        ),
    ];
  }

  static Iterable<PlannedReminder> _forKind(
    ReminderKind kind,
    ReminderTime time,
    WinterArcSession arc,
    LocalDate today,
    DateTime now,
  ) sync* {
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = today.addDays(offset);
      final position = arc.positionOn(date);
      if (position is! ArcInProgress) continue;
      // The local constructor applies the device's time zone and daylight
      // saving for that date.
      final at = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!at.isAfter(now)) continue;
      final day = position.dayNumber;
      yield PlannedReminder(
        id: kind._idBase + offset,
        kind: kind,
        at: at,
        title: switch (kind) {
          ReminderKind.daily => 'Winter Arc · Day $day',
          ReminderKind.reflection => 'How did today go?',
        },
        body: switch (kind) {
          ReminderKind.daily => 'Your Winter Arc is waiting.',
          ReminderKind.reflection => 'Take 20 seconds to reflect on Day $day.',
        },
      );
    }
  }
}
