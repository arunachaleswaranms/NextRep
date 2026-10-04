import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Closes out a Winter Arc once it is over.
///
/// The arc stays [WinterArcStatus.active] for the whole of Day 92. From the
/// first local date after [WinterArcSession.endDate], [reconcile] marks it
/// [WinterArcStatus.completed]. There is no background job: the app calls
/// [reconcile] at its entry points (launch, resume, Today / Journey refresh),
/// so the close-out happens the first time the app is used after the arc.
final class ArcLifecycleService {
  ArcLifecycleService({required this._sessions, required this._clock});

  final WinterArcRepository _sessions;
  final Clock _clock;
  final _queue = SerialQueue();

  /// Brings the latest session's status in line with today's date and
  /// returns it (null if there is no session).
  ///
  /// Idempotent: it writes at most once per arc, never closes an arc early,
  /// and leaves setup and completed sessions untouched.
  Future<WinterArcSession?> reconcile() => _queue.run(() async {
    final session = await _sessions.latestSession();
    if (session == null ||
        session.status != WinterArcStatus.active ||
        !session.isOverOn(_clock.today())) {
      return session;
    }
    final completed = session.copyWith(status: WinterArcStatus.completed);
    await _sessions.updateSession(completed);
    return completed;
  });
}
