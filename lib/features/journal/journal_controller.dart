import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/reflection/daily_reflection.dart';
import '../../domain/reflection/reflection_service.dart';
import '../achievements/achievements_controller.dart';

/// Bumped after a reflection is saved, so views that count reflections
/// (Arc History) re-read.
final reflectionsChangedProvider = NotifierProvider<_Counter, int>(
  _Counter.new,
);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final journalControllerProvider =
    AsyncNotifierProvider.autoDispose<JournalController, JournalView>(
      JournalController.new,
    );

/// The active arc's Journal. The state is re-read from storage after each
/// save, so what the UI shows is what was persisted.
class JournalController extends AsyncNotifier<JournalView> {
  final _queue = SerialQueue();

  @override
  Future<JournalView> build() => ref.watch(reflectionServiceProvider).journal();

  /// Saves today's reflection for the arc and day on screen.
  ///
  /// Reflection achievements are reconciled afterwards, best effort: their
  /// failure never fails or undoes the save.
  Future<ActionResult<ReflectionSave>> save(ReflectionDraft draft) {
    final shown = state.value;
    final service = ref.read(reflectionServiceProvider);
    final achievements = ref.read(achievementSyncProvider);
    final changed = ref.read(reflectionsChangedProvider.notifier);
    final result = _queue.run(() async {
      final ActionResult<ReflectionSave> result = shown == null
          ? const ActionFailure<ReflectionSave>(
              DomainFailure(DomainRule.noActiveSession, 'Journal not loaded'),
            )
          : await runAction(
              'journal',
              () => service.save(
                sessionId: shown.session.id,
                date: shown.today,
                draft: draft,
              ),
            );
      if (result is ActionSuccess) changed.bump();
      await _reload(service);
      return result;
    });
    _queue.run(() async {
      if (await result is ActionSuccess) await achievements.run();
    });
    return result;
  }

  /// Re-reads the Journal, e.g. when the app resumes on a new day.
  Future<void> refresh() =>
      _queue.run(() => _reload(ref.read(reflectionServiceProvider)));

  Future<void> _reload(ReflectionService service) async {
    if (!ref.mounted) return;
    final next = await AsyncValue.guard(service.journal);
    if (next case AsyncError(:final error, :final stackTrace)) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'journal');
    }
    if (ref.mounted) state = next;
  }
}

/// The Journal of the started arc [sessionId], for Arc History. Read-only.
final arcJournalProvider = FutureProvider.autoDispose.family<JournalView, int>(
  (ref, sessionId) =>
      ref.watch(reflectionServiceProvider).journalFor(sessionId),
);
