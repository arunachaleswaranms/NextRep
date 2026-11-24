import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';
import '../../domain/habit/habit.dart';
import '../../domain/reminder/reminder_preferences.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/habit_labels.dart';

/// The wording of Habit Setup's ordering, Save for Later, the saved-setup
/// hub, Review Setup and Confirm & Start (Phase 12D, owner Gate D), in one
/// place. Pure: no clock, no storage. Every date comes from the [ArcSetup]
/// snapshot the screen shows.
abstract final class SetupLabels {
  static const days = WinterArcRules.lengthInDays;

  // Ordering (Habit Setup).
  static const reorderHint = 'Hold and drag to put them in your order.';
  static const moveUp = 'Move up';
  static const moveDown = 'Move down';
  static const reorderFailed = "Couldn't save the new order.";

  /// The drag handle's name: "Reorder Water".
  static String reorderHandle(Habit habit) => 'Reorder ${habit.title}';

  /// A setup habit card as a screen reader reads it: "Water, 8 glasses,
  /// on, 2 of 8".
  static String habitCard(Habit habit, {required int index, required int of}) =>
      '${habit.title}, ${targetLabel(habit, habit.target)}, '
      '${habit.enabled ? 'on' : 'off'}, ${index + 1} of $of';

  /// Announced after a move: "Water moved to position 1 of 8".
  static String moved(Habit habit, {required int index, required int of}) =>
      '${habit.title} moved to position ${index + 1} of $of';

  // Save for Later.
  static const saveForLater = 'Save for Later';
  static const saved = 'Your Arc setup is saved.';
  static const savedDetail = 'It stays here until you start it.';

  // Actions shared by the setup screens.
  static const reviewAndStart = 'Review & Start';
  static const startChallenge = 'Start Challenge';
  static const reviewSetup = 'Review Setup';
  static const continueEditing = 'Continue Editing';
  static const continueToStart = 'Continue to Start';
  static const editSetup = 'Edit Setup';

  /// Habit Setup's link under Save for Later.
  static const cancelSetup = 'Cancel setup';

  /// The hub's bottom button, in Title Case like its siblings and the
  /// dialog's own "Cancel Setup" (Gate H copy C-1).
  static const hubCancelSetup = 'Cancel Setup';

  // The hub.
  static const hubEyebrow = 'YOUR WINTER ARC';
  static const hubTitle = 'Your Arc Setup Is Saved';
  static const settingsHeading = 'SETTINGS AND HISTORY';

  /// "Rolling 92-Day · 8 habits · 7 on".
  static String hubSummary(ArcSetup setup) {
    final count = setup.habits.length;
    return '${kindShort(setup.session)} · $count '
        '${count == 1 ? 'habit' : 'habits'} · ${setup.enabledCount} on';
  }

  /// When the arc's days will be, as the hub and Habit Setup say it.
  static String whenItStarts(ArcSetup setup) => switch (setup.startState) {
    SetupStartState.seasonNotStarted => seasonNotStarted,
    SetupStartState.seasonEnded => seasonEnded,
    SetupStartState.ready when !setup.session.isSeasonal =>
      'Day 1 will be the day you start.',
    SetupStartState.ready =>
      setup.todayDay == 1
          ? 'The season starts today: Day 1 of $days.'
          : 'The season is on Day ${setup.todayDay} of $days. Join now and '
                'start on Day ${setup.todayDay}.',
  };

  static const seasonNotStarted =
      'Season starts October 1. Your setup is saved until then.';
  static const seasonEnded =
      'This season has ended. Cancel this setup to choose a new Arc.';

  /// Why Start is unavailable, said under the disabled button and as part
  /// of its accessible name; null when it can start.
  static String? blocked(ArcSetup setup) => switch (setup.blocker) {
    null => null,
    SetupBlocker.noHabits => addAHabit,
    SetupBlocker.noneEnabled => turnOneOn,
    SetupBlocker.seasonNotStarted => seasonNotStarted,
    SetupBlocker.seasonEnded => seasonEnded,
  };

  static const addAHabit = 'Add a habit to start.';
  static const turnOneOn = 'Turn on at least one habit to start.';

  /// A disabled button's accessible name with its reason.
  static String unavailable(String action, String reason) =>
      '$action, unavailable. $reason';

  // Review Setup.
  static const noHabitsYet = 'No habits yet.';
  static const noneOn = 'No habits are on.';

  /// "Rolling 92-Day Arc" or "Seasonal Winter Arc".
  static String kindTitle(WinterArcSession session) =>
      session.isSeasonal ? 'Seasonal Winter Arc' : 'Rolling 92-Day Arc';

  /// "Rolling 92-Day" or "Seasonal".
  static String kindShort(WinterArcSession session) =>
      session.isSeasonal ? 'Seasonal' : 'Rolling 92-Day';

  /// Review's date line: "Starts the day you confirm · 92 days", or the
  /// season's dates.
  static String reviewDates(ArcSetup setup) => setup.session.isSeasonal
      ? '${shortDate(setup.session.startDate)} – '
            '${shortDate(setup.session.endDate)} · $days days'
      : 'Starts the day you confirm · $days days';

  static String habitsHeading(int count) => 'YOUR HABITS ($count)';
  static String offHeading(int count) => 'OFF ($count)';

  /// "8 glasses · Min 4", "Before 23:00", "Daily goal".
  static String goals(Habit habit) => switch (habit.type) {
    HabitType.count || HabitType.duration =>
      '${targetLabel(habit, habit.target)} · Min '
          '${targetLabel(habit, habit.minimumTarget)}',
    _ => targetLabel(habit, habit.target),
  };

  /// "1. Water. 8 glasses. Minimum 4." (an enabled habit), "Reading. Daily
  /// goal. Off." (a disabled one).
  static String reviewHabit(Habit habit, {int? position}) {
    final goal = switch (habit.type) {
      HabitType.count || HabitType.duration =>
        '${targetLabel(habit, habit.target)}. Minimum '
            '${targetLabel(habit, habit.minimumTarget)}.',
      _ => '${targetLabel(habit, habit.target)}.',
    };
    return position == null
        ? '${habit.title}. $goal Off.'
        : '$position. ${habit.title}. $goal';
  }

  /// "Reminders: Daily 08:00 · Reflection off · Hydration Coach off".
  static String reminders(ReminderPreferences p) =>
      'Reminders: '
      'Daily ${p.dailyEnabled ? p.dailyTime : 'off'} · '
      'Reflection ${p.reflectionEnabled ? p.reflectionTime : 'off'} · '
      'Hydration Coach ${p.hydrationEnabled ? 'on' : 'off'}';

  static const remindersWait = 'Reminders begin once your Arc starts.';
  static const remindersUnknown = "Reminders: couldn't be read just now.";

  // Confirm & Start.
  static const confirmTitle = 'Start your Winter Arc?';

  static String confirmButton(WinterArcSession session) => session.isSeasonal
      ? 'Confirm & Join Season'
      : 'Confirm & Start Challenge';

  /// "Rolling 92-Day Arc · 7 habits".
  static String confirmSummary(ArcSetup setup) {
    final on = setup.enabledCount;
    return '${kindTitle(setup.session)} · $on ${on == 1 ? 'habit' : 'habits'}';
  }

  /// "Today, Fri 13 Nov 2026".
  static String todayDate(LocalDate date) => 'Today, ${shortDate(date)}';

  /// What starting means, for a rolling arc. The Gate C wording: a day
  /// with nothing logged reads "No progress", never "missed".
  static const rollingConsequence =
      'Starting begins the count today. Days with nothing logged show as '
      'No progress. Not ready? Save it and start another day.';

  /// "You join today on Day 18 of 92." for a seasonal arc.
  static String seasonalJoin(int day) => 'You join today on Day $day of $days.';

  /// What joining means, for a seasonal arc.
  static String seasonalConsequence(ArcSetup setup) =>
      "${setup.todayDay == 1 ? '' : "Earlier days won't count against you. "}"
      'The season ends ${shortDate(setup.session.endDate)}. Not ready? '
      'Save it and join another day.';

  static const startFailed = "Couldn't start. Nothing was changed.";

  /// "Fri 13 Nov 2026".
  static String shortDate(LocalDate date) =>
      DateFormat('EEE d MMM y').format(date.toLocalDateTime());

  /// "Friday 13 November 2026", as a screen reader says a date.
  static String fullDate(LocalDate date) =>
      DateFormat('EEEE d MMMM y').format(date.toLocalDateTime());
}
