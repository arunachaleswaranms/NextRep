import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/celebration/celebration_queue.dart';

/// Generation of the app's routed UI. Bumping it rebuilds the router and
/// every screen from storage, as a relaunch would, so nothing on screen or
/// in a screen's state can outlive a restore.
final appEpochProvider = NotifierProvider<AppEpoch, int>(AppEpoch.new);

class AppEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// Reloads the app's state from storage after all of it was replaced:
  /// re-resolves the arcs, recomputes the boot location, rebuilds the
  /// router and every screen, and drops queued celebrations (they belong
  /// to the replaced data). [notice] is shown once the app is back.
  void restart({String? notice}) {
    ref.read(celebrationQueueProvider.notifier).clear();
    ref.read(appNoticeProvider.notifier).post(notice);
    state++;
  }
}

/// A one-off message for the user, shown by the app shell as a snack bar
/// and then cleared.
final appNoticeProvider = NotifierProvider<AppNotice, String?>(AppNotice.new);

class AppNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void post(String? message) => state = message;

  /// Returns the pending message, if any, and clears it.
  String? take() {
    final message = state;
    state = null;
    return message;
  }
}
