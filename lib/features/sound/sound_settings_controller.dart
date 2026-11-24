import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/feedback/feedback_preferences.dart';

final soundSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      SoundSettingsController,
      FeedbackPreferences
    >(SoundSettingsController.new);

/// Sound & Feedback (spec § 8.4): the stored `feedback_preferences` row.
///
/// The screen always shows what is stored. Each change is written at once
/// and the row is read back afterwards, whether the write worked or not, so
/// a failed write leaves the stored value on screen, never the unsaved one.
class SoundSettingsController extends AsyncNotifier<FeedbackPreferences> {
  final _queue = SerialQueue();

  @override
  Future<FeedbackPreferences> build() =>
      ref.watch(feedbackPreferencesRepositoryProvider).load();

  /// Applies [change] to the stored settings (not to what is on screen,
  /// which may be a save behind) and returns what was stored.
  Future<ActionResult<FeedbackPreferences>> save(
    FeedbackPreferences Function(FeedbackPreferences current) change,
  ) {
    final repository = ref.read(feedbackPreferencesRepositoryProvider);
    final clock = ref.read(clockProvider);
    return _queue.run(() async {
      final result = await runAction('sound_settings', () async {
        final next = change(await repository.load());
        await repository.save(next, at: clock.now());
        return next;
      });
      if (ref.mounted) ref.invalidateSelf();
      return result;
    });
  }
}
