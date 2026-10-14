import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../domain/focus_guard/focus_guard_service.dart';
import 'focus_guard_controller.dart';

/// Focus Guard's status for the entry points outside Today. Null while it
/// loads or if it can't be read: the entry then stays hidden.
final focusGuardEntryProvider = FutureProvider.autoDispose<FocusGuardStatus?>((
  ref,
) async {
  ref.watch(focusGuardChangedProvider);
  try {
    return await ref.watch(focusGuardServiceProvider).status();
  } catch (_) {
    return null;
  }
});

/// Opens Focus Guard's settings from Arc History, so they stay reachable
/// without an active Arc (Focus Guard is app-level and can stay on after an
/// Arc ends). Hidden where Focus Guard is unsupported.
class FocusGuardButton extends ConsumerWidget {
  const FocusGuardButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(focusGuardEntryProvider).value;
    if (status == null || !status.supported) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Focus Guard',
      icon: const Icon(Icons.shield_outlined),
      onPressed: () => context.push(AppRoutes.focusGuard),
    );
  }
}

/// On onboarding, shown only while Focus Guard is on (e.g. after the last
/// Arc was deleted), so it can always be turned off from inside NextRep.
class FocusGuardOnLink extends ConsumerWidget {
  const FocusGuardOnLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(focusGuardEntryProvider).value;
    if (status == null || !status.supported || !status.settings.enabled) {
      return const SizedBox.shrink();
    }
    return Center(
      child: TextButton.icon(
        onPressed: () => context.push(AppRoutes.focusGuard),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Focus Guard is on'),
      ),
    );
  }
}
