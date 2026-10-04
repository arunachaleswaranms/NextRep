import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../winter_arc/current_arc_service.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'daily_reflection.dart';
import 'reflection_repository.dart';

/// Read model for a Journal: one arc's reflections.
final class JournalView {
  JournalView({
    required this.session,
    required this.today,
    required this.todayEntry,
    required this.past,
    required this.canWriteToday,
  });

  final WinterArcSession session;

  /// The local date when this view was built.
  final LocalDate today;

  /// Today's reflection, if saved. Always null for an arc that isn't
  /// running today.
  final DailyReflection? todayEntry;

  /// Every other reflection of the arc, newest first. Read-only. Dates
  /// without a reflection simply have no entry.
  final List<DailyReflection> past;

  /// Today's reflection can be written: the arc is active and today is
  /// one of its days.
  final bool canWriteToday;

  /// 1-based challenge day of [date] in this arc.
  int dayNumberOf(LocalDate date) => session.dayNumberOf(date);

  int get count => past.length + (todayEntry == null ? 0 : 1);
}

/// The result of saving today's reflection.
final class ReflectionSave {
  const ReflectionSave({required this.reflection, required this.created});

  final DailyReflection reflection;

  /// False when an existing reflection for the day was updated.
  final bool created;
}

/// Nightly reflection use cases.
///
/// Edit rules: only today's reflection of the active arc can be written.
/// Earlier dates are read-only, later dates aren't open yet, and every
/// reflection of a completed arc is read-only.
final class ReflectionService {
  ReflectionService({
    required WinterArcRepository sessions,
    required this._reflections,
    required this._clock,
  }) : _arcs = CurrentArcService(sessions);

  final CurrentArcService _arcs;
  final ReflectionRepository _reflections;
  final Clock _clock;
  final _queue = SerialQueue();

  /// The Journal of the home arc (active, or just completed).
  Future<JournalView> journal() async => _journalOf(await _arcs.requireHome());

  /// The Journal of the started arc [sessionId], for history.
  Future<JournalView> journalFor(int sessionId) async =>
      _journalOf(await _arcs.requireStarted(sessionId));

  /// Saves the reflection for [date] of arc [sessionId]. [date] must be
  /// today and [sessionId] the active arc. A second save on the same day
  /// updates the reflection instead of adding another.
  Future<ReflectionSave> save({
    required int sessionId,
    required LocalDate date,
    required ReflectionDraft draft,
  }) => _queue.run(() async {
    final content = ReflectionRules.validate(draft);
    final session = await _arcs.requireWritable(sessionId: sessionId);
    final today = _clock.today();
    if (date.isBefore(today)) {
      throw const DomainFailure(
        DomainRule.reflectionReadOnly,
        'Only today can be reflected on',
      );
    }
    if (date.isAfter(today) || session.positionOn(date) is! ArcInProgress) {
      throw const DomainFailure(
        DomainRule.reflectionNotAvailable,
        'That date is not open for a reflection',
      );
    }
    final existing = await _reflections.reflectionOn(session.id, date);
    final saved = await _reflections.save(
      sessionId: session.id,
      date: date,
      content: content,
      at: _clock.now(),
    );
    return ReflectionSave(reflection: saved, created: existing == null);
  });

  Future<JournalView> _journalOf(WinterArcSession session) async {
    final today = _clock.today();
    final canWrite =
        session.status == WinterArcStatus.active &&
        session.positionOn(today) is ArcInProgress;
    final all = await _reflections.reflectionsFor(session.id);
    final todayEntry = canWrite
        ? all.where((r) => r.date == today).firstOrNull
        : null;
    return JournalView(
      session: session,
      today: today,
      todayEntry: todayEntry,
      past: [
        for (final r in all)
          if (r != todayEntry) r,
      ],
      canWriteToday: canWrite,
    );
  }
}
