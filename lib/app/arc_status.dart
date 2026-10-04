import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/winter_arc/current_arc_service.dart';
import 'dependencies.dart';

/// Where the app stands across the user's arcs: the unfinished arc, if
/// any, and the latest completed one. The router listens to it, so a
/// close-out, a new setup or a start moves the app to the right place
/// wherever the user is. Null until first resolved at launch.
final arcResolutionProvider =
    NotifierProvider<ArcResolutionController, ArcResolution?>(
      ArcResolutionController.new,
    );

class ArcResolutionController extends Notifier<ArcResolution?> {
  @override
  ArcResolution? build() => null;

  /// Runs the arc close-out check (at launch, resume, Today / Journey
  /// refresh, and after an arc is created or started) and publishes the
  /// result.
  Future<ArcResolution> reconcile() async {
    final resolution = await ref.read(arcLifecycleServiceProvider).resolve();
    if (ref.mounted) state = resolution;
    return resolution;
  }
}
