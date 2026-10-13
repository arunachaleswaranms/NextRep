import '../../core/time/local_date.dart';
import '../winter_arc/winter_arc_session.dart';
import 'hydration_planner.dart';
import 'reminder_preferences.dart';

/// The reminder types. [payload] is what a tapped notification hands back
/// to the app, so never change an existing payload.
///
/// Notification ids are `idBase + day offset` for daily and reflection
/// reminders (offsets 0..13) and `idBase + 10 × day offset + slot` for
/// hydration (offsets 0..6, slots 0..4): 100–113, 200–213 and 300–364,
/// which never collide. They follow from the plan alone and are never
/// stored.
enum ReminderKind {
  /// Opens Today.
  daily('today', 100),

  /// Opens today's reflection in the Journal.
  reflection('journal', 200),

  /// A Hydration Coach nudge. Opens Today.
  hydration('hydration', 300);

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

  /// Whether [other] would show the same notification at the same time.
  bool sameAs(PlannedReminder other) =>
      other.id == id &&
      other.kind == kind &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  String toString() => 'PlannedReminder(${kind.name}, $at)';
}

/// The scheduler calls that turn the pending notifications into a new plan
/// without touching the ones that stay the same.
///
/// A water log re-plans every reminder; only the hydration nudges that
/// changed are rescheduled, and daily and reflection reminders are left as
/// they are.
final class ReminderChanges {
  const ReminderChanges({required this.cancel, required this.schedule});

  /// [pending]: ids the OS holds as pending (never one already shown).
  /// [known]: what this process last scheduled under each id. A pending id
  /// whose content isn't known is scheduled again, which replaces it.
  factory ReminderChanges.between({
    required Set<int> pending,
    required Map<int, PlannedReminder> known,
    required List<PlannedReminder> next,
  }) {
    final wanted = {for (final reminder in next) reminder.id};
    return ReminderChanges(
      cancel: [
        for (final id in pending)
          if (!wanted.contains(id)) id,
      ]..sort(),
      schedule: [
        for (final reminder in next)
          if (!pending.contains(reminder.id) ||
              !(known[reminder.id]?.sameAs(reminder) ?? false))
            reminder,
      ],
    );
  }

  /// Pending ids no longer in the plan.
  final List<int> cancel;

  /// Reminders to (re)schedule; scheduling an id replaces what it held.
  final List<PlannedReminder> schedule;
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
///
/// The plan is always complete (daily, reflection and hydration together),
/// because the scheduler replaces every pending reminder with it.
abstract final class ReminderPlanner {
  /// How many days ahead daily and reflection reminders are planned.
  /// Opening the app at least once in that window keeps them going; after
  /// that they pause on their own instead of nagging someone who has
  /// stepped away. Hydration uses [HydrationPlanner.horizonDays].
  static const int horizonDays = 14;

  /// Most reminders a plan can hold: 14 daily, 14 reflection and 7 days of
  /// at most 5 hydration nudges. Within iOS's 64 pending notifications.
  static const int maxPending =
      2 * horizonDays +
      HydrationPlanner.horizonDays * HydrationPlanner.maxNudgesPerDay;

  /// Hydration notification copy. Generic on purpose: a lock screen never
  /// shows amounts, targets or habit names.
  static const hydrationTitle = 'Hydration check';
  static const hydrationBody = 'A little water now can keep you on pace.';

  /// The reminders that should be pending at [now] for [preferences], given
  /// the [active] arc (null when no arc is running) and, for Hydration
  /// Coach, the state of the next [HydrationPlanner.horizonDays] days
  /// ([hydration], from today on).
  static List<PlannedReminder> plan({
    required ReminderPreferences preferences,
    required WinterArcSession? active,
    required DateTime now,
    List<HydrationDay> hydration = const [],
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
      if (preferences.hydrationEnabled)
        ..._hydration(preferences, active, hydration, today, now),
    ];
  }

  static Iterable<PlannedReminder> _hydration(
    ReminderPreferences preferences,
    WinterArcSession arc,
    List<HydrationDay> days,
    LocalDate today,
    DateTime now,
  ) sync* {
    final checkpoints = HydrationPlanner.plan(
      mode: preferences.hydrationMode,
      window: preferences.hydrationWindow,
      days: [
        for (final day in days)
          if (_isHydrationDay(day.date, today) &&
              arc.positionOn(day.date) is ArcInProgress)
            day,
      ],
      now: now,
    );
    for (final checkpoint in checkpoints) {
      yield PlannedReminder(
        id:
            ReminderKind.hydration._idBase +
            10 * today.daysUntil(checkpoint.date) +
            checkpoint.slot,
        kind: ReminderKind.hydration,
        at: checkpoint.at,
        title: hydrationTitle,
        body: hydrationBody,
      );
    }
  }

  static bool _isHydrationDay(LocalDate date, LocalDate today) {
    final offset = today.daysUntil(date);
    return offset >= 0 && offset < HydrationPlanner.horizonDays;
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
          ReminderKind.hydration => hydrationTitle,
        },
        body: switch (kind) {
          ReminderKind.daily => 'Your Winter Arc is waiting.',
          ReminderKind.reflection => 'Take 20 seconds to reflect on Day $day.',
          ReminderKind.hydration => hydrationBody,
        },
      );
    }
  }
}
