import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/winter_arc/winter_arc_session.dart';
import 'dependencies.dart';

/// The latest known lifecycle status of the arc. The router listens to it,
/// so a close-out moves the app to the summary wherever the user is.
final arcStatusProvider =
    NotifierProvider<ArcStatusController, WinterArcStatus?>(
      ArcStatusController.new,
    );

class ArcStatusController extends Notifier<WinterArcStatus?> {
  @override
  WinterArcStatus? build() => null;

  /// Runs the arc close-out check (at launch, resume and Today / Journey
  /// refresh) and publishes the resulting status.
  Future<WinterArcSession?> reconcile() async {
    final session = await ref.read(arcLifecycleServiceProvider).reconcile();
    if (ref.mounted) state = session?.status;
    return session;
  }

  /// Records a status change made elsewhere (e.g. the arc was started).
  void set(WinterArcStatus? status) => state = status;
}
