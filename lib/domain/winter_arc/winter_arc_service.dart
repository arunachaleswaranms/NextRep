import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../habit/habit_repository.dart';
import '../habit/habit_template_catalog.dart';
import '../habit/setup_habit_rules.dart';
import '../habit/starter_habits.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Which habits a new arc starts from.
enum NewArcBaseline {
  /// The starter catalogue, exactly as on a first install.
  fresh,

  /// The final configuration of the most recently completed arc.
  reuseLast,
}

/// Whether an arc in setup can start today.
enum SetupStartState {
  /// Start is available.
  ready,

  /// A Seasonal Winter Arc set up in September: it can only start from
  /// 1 October.
  seasonNotStarted,

  /// A Seasonal Winter Arc whose season is over without it ever starting.
  /// It can only be cancelled; it is never moved to another year.
  seasonEnded,
}

/// Pure start rules for an arc in setup.
abstract final class ArcStartRules {
  /// Whether [session] (in setup) can start on [today].
  static SetupStartState stateOn(WinterArcSession session, LocalDate today) {
    if (!session.isSeasonal) return SetupStartState.ready;
    if (today.isBefore(session.startDate)) {
      return SetupStartState.seasonNotStarted;
    }
    if (today.isAfter(session.endDate)) return SetupStartState.seasonEnded;
    return SetupStartState.ready;
  }

  /// [session] started on [today] at [now]:
  ///
  /// * rolling: Day 1 is today, Day 92 is today + 91, joined today
  /// * seasonal: 1 October – 31 December stay as they are, joined today
  ///   (so a late join is on the season's own day number, never Day 1)
  ///
  /// Throws [DomainRule.seasonNotStarted] before 1 October and
  /// [DomainRule.seasonEnded] after 31 December.
  static WinterArcSession start(
    WinterArcSession session, {
    required LocalDate today,
    required DateTime now,
  }) {
    switch (stateOn(session, today)) {
      case SetupStartState.seasonNotStarted:
        throw const DomainFailure(
          DomainRule.seasonNotStarted,
          'The season has not started',
        );
      case SetupStartState.seasonEnded:
        throw const DomainFailure(
          DomainRule.seasonEnded,
          'The season of this setup has ended',
        );
      case SetupStartState.ready:
        break;
    }
    return switch (session.kind) {
      ArcKind.rolling92 => session.copyWith(
        startDate: today,
        endDate: WinterArcRules.endDateFor(today),
        participationStartDate: today,
        status: WinterArcStatus.active,
        startedAt: now,
      ),
      ArcKind.seasonalWinter => session.copyWith(
        participationStartDate: today,
        status: WinterArcStatus.active,
        startedAt: now,
      ),
    };
  }
}

/// An arc in setup with its habits, as Habit Setup shows it.
final class ArcSetup {
  const ArcSetup({
    required this.session,
    required this.habits,
    required this.startState,
    required this.today,
  });

  final WinterArcSession session;

  /// In display order.
  final List<Habit> habits;
  final SetupStartState startState;

  /// The date [startState] was decided on, so everything Habit Setup shows
  /// comes from the same moment (never a widget's own clock read).
  final LocalDate today;

  /// The season day number of [today] for this arc (a late join shows
  /// "Day 15"), or 1 for a rolling arc.
  int get todayDay => session.dayNumberOf(today);

  int get enabledCount => habits.where((h) => h.enabled).length;

  /// No more habits can be added.
  bool get atHabitLimit => habits.length >= SetupHabitRules.maxHabits;

  /// Start is available: the season allows it and a habit is on.
  bool get canStart => startState == SetupStartState.ready && enabledCount > 0;
}

/// Use cases for configuring and starting a Winter Arc, including every arc
/// after the first.
///
/// Mutations run through a [SerialQueue] so that concurrent calls (e.g. a
/// double tap on "Let's Begin") observe each other's results instead of
/// racing, which keeps [beginSetup] and [startWinterArc] idempotent.
final class WinterArcService {
  WinterArcService({
    required this._sessions,
    required this._habits,
    required this._clock,
    HabitIdGenerator? ids,
  }) : _ids = ids ?? SecureHabitIdGenerator();

  final WinterArcRepository _sessions;
  final HabitRepository _habits;
  final Clock _clock;
  final HabitIdGenerator _ids;
  final _mutations = SerialQueue();

  /// The unfinished arc (setup or active), or null.
  Future<WinterArcSession?> currentSession() => _sessions.currentSession();

  /// The Seasonal Winter Arc of today's local calendar year.
  SeasonAvailability seasonAvailability() =>
      SeasonalWinterRules.availabilityOn(_clock.today());

  /// Creates a session in setup with the starter habits, for a user with no
  /// arc yet (or one who starts fresh).
  ///
  /// Idempotent: if an unfinished session exists it is returned unchanged.
  /// Throws [DomainRule.seasonNotOpen] for a seasonal arc before
  /// 1 September.
  Future<WinterArcSession> beginSetup({ArcKind kind = ArcKind.rolling92}) =>
      _mutations.run(() async {
        final existing = await _sessions.currentSession();
        if (existing != null) return existing;
        return _createSetup(kind, StarterHabits.seed(_clock.now()));
      });

  /// Creates the setup session of a new arc of [kind]. A rolling arc's
  /// start date stays provisional until [startWinterArc]; a seasonal arc is
  /// always this year's 1 October – 31 December.
  ///
  /// [NewArcBaseline.reuseLast] copies each habit's final effective
  /// configuration (see [reusableHabits]); nothing else carries over:
  /// progress, XP, streaks, day modes, revisions, achievements and
  /// reflections stay with the arc that earned them, which is never written.
  /// The kind is chosen here, never copied: a seasonal arc's habits can
  /// start a rolling arc and the other way round.
  ///
  /// Throws [DomainRule.arcInProgress] if an arc is already in setup or
  /// running, [DomainRule.noCompletedArc] when reusing without a completed
  /// arc and [DomainRule.seasonNotOpen] for a seasonal arc before
  /// 1 September.
  Future<WinterArcSession> startNewArc(
    NewArcBaseline baseline, {
    ArcKind kind = ArcKind.rolling92,
  }) => _mutations.run(() async {
    if (await _sessions.currentSession() != null) {
      throw const DomainFailure(
        DomainRule.arcInProgress,
        'An arc is already in setup or running',
      );
    }
    final now = _clock.now();
    final habits = switch (baseline) {
      NewArcBaseline.fresh => StarterHabits.seed(now),
      NewArcBaseline.reuseLast => await _reusable(createdAt: now),
    };
    if (habits == null) {
      throw const DomainFailure(
        DomainRule.noCompletedArc,
        'No completed arc to reuse',
      );
    }
    return _createSetup(kind, habits);
  });

  /// The habits "Reuse last setup" would start with, or null when no arc
  /// has been completed.
  Future<List<Habit>?> reusableHabits() => _reusable(createdAt: _clock.now());

  Future<List<Habit>> setupHabits() async {
    final session = await _requireSetup();
    return _habits.habitsForSession(session.id);
  }

  /// The arc in setup, its habits and whether it can start today.
  Future<ArcSetup> setup() async {
    final session = await _requireSetup();
    final today = _clock.today();
    return ArcSetup(
      session: session,
      habits: await _habits.habitsForSession(session.id),
      startState: ArcStartRules.stateOn(session, today),
      today: today,
    );
  }

  /// Adds the catalogue template [templateId] to the arc in setup, switched
  /// on. Throws [DomainRule.duplicateHabit] if it (or a habit of the same
  /// name) is already there and [DomainRule.habitLimitReached] at the
  /// limit.
  Future<Habit> addTemplateHabit(String templateId) => _mutations.run(() async {
    final template = HabitTemplateCatalog.byId(templateId);
    if (template == null) {
      throw DomainFailure(
        DomainRule.habitNotFound,
        'No template "$templateId"',
      );
    }
    final session = await _requireSetup();
    final habit = SetupHabitRules.fromTemplate(
      template,
      await _habits.habitsForSession(session.id),
      createdAt: _clock.now(),
    );
    await _habits.addSetupHabit(session.id, habit);
    return habit;
  });

  /// Creates a habit of the user's own in the arc in setup, switched on,
  /// with a new random id (see [SecureHabitIdGenerator]).
  ///
  /// Only possible in setup: a running arc's habits are fixed (they can be
  /// switched off instead). Throws [DomainRule.invalidHabitEdit] for an
  /// invalid draft, [DomainRule.duplicateHabit] for a name already used and
  /// [DomainRule.habitLimitReached] at the limit.
  Future<Habit> addCustomHabit(HabitDraft draft) => _mutations.run(() async {
    final session = await _requireSetup();
    final habit = SetupHabitRules.create(
      draft,
      await _habits.habitsForSession(session.id),
      id: _ids.next(),
      createdAt: _clock.now(),
    );
    await _habits.addSetupHabit(session.id, habit);
    return habit;
  });

  /// Changes habit [habitId] of the arc in setup to [draft]: its baseline
  /// is rewritten directly, without revisions, since nothing has happened
  /// yet.
  Future<Habit> editSetupHabit(String habitId, HabitDraft draft) =>
      _mutations.run(() async {
        final session = await _requireSetup();
        final habits = await _habits.habitsForSession(session.id);
        final habit = _find(habits, habitId);
        final edited = SetupHabitRules.edit(habit, draft, habits);
        if (!await _habits.updateSetupHabit(session.id, edited)) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
        return edited;
      });

  /// Deletes habit [habitId] from the arc in setup. A running arc's habits
  /// can't be deleted (switch them off instead). The setup may be left with
  /// no habits for a moment; it just can't start like that.
  Future<void> deleteSetupHabit(String habitId) => _mutations.run(() async {
    final session = await _requireSetup();
    if (!await _habits.deleteSetupHabit(session.id, habitId)) {
      throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
    }
  });

  static Habit _find(List<Habit> habits, String habitId) {
    for (final habit in habits) {
      if (habit.id == habitId) return habit;
    }
    throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
  }

  Future<void> setHabitEnabled(String habitId, {required bool enabled}) =>
      _mutations.run(() async {
        final session = await _requireSetup();
        final found = await _habits.setEnabled(
          session.id,
          habitId,
          enabled: enabled,
        );
        if (!found) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
      });

  /// Starts the current arc today (see [ArcStartRules.start]): a rolling
  /// arc's Day 1 is today; a seasonal arc keeps 1 October as Day 1 and is
  /// joined today.
  ///
  /// Idempotent: calling it on an already active session returns that
  /// session. Throws [DomainRule.seasonNotStarted] / [DomainRule.seasonEnded]
  /// outside the season, whatever the UI showed.
  Future<WinterArcSession> startWinterArc() => _mutations.run(() async {
    final session = await _sessions.currentSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session to start');
    }
    if (session.status == WinterArcStatus.active) return session;

    final habits = await _habits.habitsForSession(session.id);
    if (!habits.any((h) => h.enabled)) {
      throw const DomainFailure(
        DomainRule.noHabitsSelected,
        'Select at least one habit to start',
      );
    }

    final started = _checked(
      ArcStartRules.start(session, today: _clock.today(), now: _clock.now()),
    );
    await _sessions.updateSession(started);
    return started;
  });

  /// Permanently deletes the completed arc [sessionId] with all of its
  /// history: habits, progress, XP, Journey, achievements and reflections.
  /// Other arcs and the reminder preferences are untouched.
  ///
  /// Only a completed arc can be deleted. Throws [DomainRule.arcNotDeletable]
  /// for an arc in setup or running (cancel a setup with [cancelSetup]) and
  /// [DomainRule.sessionNotFound] if there is no such arc.
  Future<void> deleteCompletedArc(int sessionId) => _mutations.run(() async {
    final session = await _sessions.sessionById(sessionId);
    if (session == null) {
      throw DomainFailure(DomainRule.sessionNotFound, 'No session $sessionId');
    }
    if (session.status != WinterArcStatus.completed) {
      throw DomainFailure(
        DomainRule.arcNotDeletable,
        'Session $sessionId is ${session.status.name}',
      );
    }
    await _sessions.deleteSession(
      sessionId,
      expected: WinterArcStatus.completed,
    );
  });

  /// Abandons the arc being set up, deleting it and its provisional habits.
  /// Completed arcs are untouched. A running arc can't be cancelled.
  ///
  /// Throws [DomainRule.noSession] when nothing is unfinished and
  /// [DomainRule.sessionNotInSetup] when the unfinished arc has started.
  Future<void> cancelSetup() => _mutations.run(() async {
    final session = await _requireSetup();
    await _sessions.deleteSession(session.id, expected: WinterArcStatus.setup);
  });

  Future<WinterArcSession> _createSetup(ArcKind kind, List<Habit> habits) {
    final today = _clock.today();
    final (start, end) = switch (kind) {
      ArcKind.rolling92 => (today, WinterArcRules.endDateFor(today)),
      ArcKind.seasonalWinter => () {
        final season = SeasonalWinterRules.availabilityOn(today);
        if (!season.canSetUp) {
          throw const DomainFailure(
            DomainRule.seasonNotOpen,
            'The season opens for setup on 1 September',
          );
        }
        return (season.seasonStart, season.seasonEnd);
      }(),
    };
    return _sessions.createSetupSession(
      kind: kind,
      startDate: start,
      endDate: end,
      createdAt: _clock.now(),
      habits: habits,
    );
  }

  /// [session], provided it keeps every arc invariant.
  static WinterArcSession _checked(WinterArcSession session) {
    if (WinterArcRules.problemWith(session) case final problem?) {
      throw DomainFailure(DomainRule.invalidArc, problem);
    }
    return session;
  }

  /// Each habit of the latest completed arc as it stood on its last day:
  /// the current title and the configuration in effect on the end date
  /// (from its revision history, not the original baseline). These become
  /// the new arc's baseline.
  Future<List<Habit>?> _reusable({required DateTime createdAt}) async {
    final last = await _sessions.latestCompletedSession();
    if (last == null) return null;
    final history = await _habits.historyForSession(last.id);
    return [
      for (final habit in history.habits)
        _withConfig(habit, history.configOn(habit, last.endDate), createdAt),
    ];
  }

  static Habit _withConfig(Habit habit, HabitConfig config, DateTime at) =>
      Habit(
        id: habit.id,
        title: habit.title,
        type: habit.type,
        target: config.target,
        minimumTarget: config.minimumTarget,
        unit: habit.unit,
        iconKey: habit.iconKey,
        enabled: config.enabled,
        sortOrder: habit.sortOrder,
        createdAt: at,
      );

  Future<WinterArcSession> _requireSetup() async {
    final session = await _sessions.currentSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session exists');
    }
    if (session.status != WinterArcStatus.setup) {
      throw DomainFailure(
        DomainRule.sessionNotInSetup,
        'Expected setup session, found ${session.status.name}',
      );
    }
    return session;
  }
}
