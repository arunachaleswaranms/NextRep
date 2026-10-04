import '../../core/errors/app_failure.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Where the app stands across all of a user's arcs.
final class ArcResolution {
  const ArcResolution({this.current, this.latestCompleted});

  /// The unfinished arc (setup or active), if any. It's the only arc that
  /// can still change.
  final WinterArcSession? current;

  /// The most recently completed arc, if any. Historical and read-only.
  final WinterArcSession? latestCompleted;

  /// The current arc if it's running.
  WinterArcSession? get active =>
      current?.status == WinterArcStatus.active ? current : null;

  /// The current arc if it's being set up.
  WinterArcSession? get setup =>
      current?.status == WinterArcStatus.setup ? current : null;

  /// The started arc that the app's home shows: the active arc or, when
  /// nothing is unfinished, the most recently completed one. Null while a
  /// new arc is in setup and before the first arc.
  WinterArcSession? get home => current == null ? latestCompleted : active;

  bool get isEmpty => current == null && latestCompleted == null;

  @override
  bool operator ==(Object other) =>
      other is ArcResolution &&
      _same(other.current, current) &&
      _same(other.latestCompleted, latestCompleted);

  @override
  int get hashCode => Object.hash(
    current?.id,
    current?.status,
    latestCompleted?.id,
    latestCompleted?.status,
  );

  static bool _same(WinterArcSession? a, WinterArcSession? b) =>
      a?.id == b?.id && a?.status == b?.status;
}

/// Resolves which arc a use case acts on. Every lookup is explicit: the
/// current (unfinished) arc, the arc the home shows, or an arc by id. A
/// historical screen always passes the id of the arc it shows, so it can't
/// pick up a newer arc by accident.
final class CurrentArcService {
  const CurrentArcService(this._sessions);

  final WinterArcRepository _sessions;

  /// The unfinished arc (setup or active), or null.
  Future<WinterArcSession?> current() => _sessions.currentSession();

  Future<ArcResolution> resolve() async => ArcResolution(
    current: await _sessions.currentSession(),
    latestCompleted: await _sessions.latestCompletedSession(),
  );

  /// The arc that the active-arc screens (Today, Journey, Journal) show:
  /// the active arc or, right after it closes and before anything new is
  /// set up, the arc that just completed (read-only). See
  /// [ArcResolution.home].
  ///
  /// Throws [DomainRule.noActiveSession] when no arc has started or a new
  /// one is still in setup.
  Future<WinterArcSession> requireHome() async {
    final home = (await resolve()).home;
    if (home == null) {
      throw const DomainFailure(
        DomainRule.noActiveSession,
        'No started Winter Arc',
      );
    }
    return home;
  }

  /// The session with [id]. It must have started (active or completed):
  /// a session in setup has no history yet.
  Future<WinterArcSession> requireStarted(int id) async {
    final session = await _sessions.sessionById(id);
    if (session == null) {
      throw DomainFailure(DomainRule.sessionNotFound, 'No session $id');
    }
    if (session.status == WinterArcStatus.setup) {
      throw DomainFailure(
        DomainRule.noActiveSession,
        'Session $id has not started',
      );
    }
    return session;
  }

  /// The active arc that a write to [date] (today) may change. [sessionId]
  /// is the arc the user was looking at; a write meant for an arc that is
  /// no longer active is rejected rather than applied to a different arc.
  ///
  /// Throws [DomainRule.arcCompleted] when the arc has closed and
  /// [DomainRule.noActiveSession] when nothing is running.
  Future<WinterArcSession> requireWritable({int? sessionId}) async {
    final resolution = await resolve();
    final active = resolution.active;
    if (active != null && (sessionId == null || sessionId == active.id)) {
      return active;
    }
    final closed =
        (sessionId != null && sessionId == resolution.latestCompleted?.id) ||
        (sessionId == null &&
            resolution.current == null &&
            resolution.latestCompleted != null);
    if (closed || active != null) {
      throw const DomainFailure(
        DomainRule.arcCompleted,
        'Winter Arc is complete',
      );
    }
    throw const DomainFailure(
      DomainRule.noActiveSession,
      'No active Winter Arc',
    );
  }
}
