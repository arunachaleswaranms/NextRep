import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

final onboardingControllerProvider =
    NotifierProvider.autoDispose<OnboardingController, bool>(
      OnboardingController.new,
    );

/// State is whether the "Let's Begin" action is in flight.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Persists that onboarding is done by creating the setup session.
  Future<ActionResult<WinterArcSession>> begin() async {
    state = true;
    final result = await runAction(
      'onboarding',
      () => ref.read(winterArcServiceProvider).beginSetup(),
    );
    if (ref.mounted) state = false;
    return result;
  }
}
