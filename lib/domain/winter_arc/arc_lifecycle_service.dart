import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import 'current_arc_service.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Closes out a Winter Arc once it is over.
///
/// The arc stays [WinterArcStatus.active] for the whole of Day 92. From the
/// first local date after [WinterArcSession.endDate], [reconcile] marks it
/// [WinterArcStatus.completed]. There is no background job: the app calls
/// [reconcile] at its entry points (launch, resume, Today / Journey refresh),
/// so the close-out happens the first time the app is used after the arc.
///
/// Only the current (unfinished) arc is ever examined. Completed arcs are
/// history and never written again.
final class ArcLifecycleService {
  ArcLifecycleService({required this._sessions, required this._clock});

  final WinterArcRepository _sessions;
  final Clock _clock;
  final _queue = SerialQueue();

  /// Brings the current arc's status in line with today's date and returns
  /// the arc the app is anchored on: the current arc (possibly just
  /// completed) or, with nothing unfinished, the most recently completed
  /// one. Null if there is no session at all.
  ///
  /// Idempotent: it writes at most once per arc, never closes an arc early,
  /// and leaves setup and completed sessions untouched.
  Future<WinterArcSession?> reconcile() => _queue.run(() async {
    final current = await _sessions.currentSession();
    if (current == null) return _sessions.latestCompletedSession();
    if (current.status != WinterArcStatus.active ||
        !current.isOverOn(_clock.today())) {
      return current;
    }
    final completed = current.copyWith(status: WinterArcStatus.completed);
    await _sessions.updateSession(completed);
    return completed;
  });

  /// Runs [reconcile] and then resolves the current and latest completed
  /// arcs.
  Future<ArcResolution> resolve() async {
    await reconcile();
    return CurrentArcService(_sessions).resolve();
  }
}
