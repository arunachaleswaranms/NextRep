import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../shared/feedback/haptics.dart';
import 'celebration_cards.dart';
import 'celebration_queue.dart';

/// Shows queued celebrations over the whole app, one at a time.
///
/// Each card stays for [WinterDurations.celebrationHold] or until tapped,
/// then the next one appears. It never blocks the screen below: only the
/// card itself takes touches. Its haptic plays when it appears.
class CelebrationOverlay extends ConsumerStatefulWidget {
  const CelebrationOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends ConsumerState<CelebrationOverlay> {
  CelebrationEvent? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _present(ref.read(celebrationQueueProvider).firstOrNull);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _present(CelebrationEvent? head) {
    if (identical(head, _shown)) return;
    _shown = head;
    _timer?.cancel();
    if (head == null) return;
    unawaited(switch (head) {
      DayCelebration(:final perfectStreak) when perfectStreak != null =>
        Haptics.perfectDay(),
      DayCelebration() => Haptics.levelUp(),
      AchievementCelebration() => Haptics.achievementUnlocked(),
    });
    _timer = Timer(WinterDurations.celebrationHold, () => _dismiss(head));
  }

  void _dismiss(CelebrationEvent event) {
    if (mounted) ref.read(celebrationQueueProvider.notifier).dismiss(event);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      celebrationQueueProvider,
      (_, queue) => _present(queue.firstOrNull),
    );
    final head = ref.watch(celebrationQueueProvider).firstOrNull;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WinterSpacing.lg,
                vertical: WinterSpacing.md,
              ),
              child: AnimatedSwitcher(
                duration: context.motion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: head == null
                    ? const SizedBox.shrink()
                    : ConstrainedBox(
                        key: ObjectKey(head),
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: SizedBox(
                          width: double.infinity,
                          child: CelebrationCard(
                            event: head,
                            onDismiss: () => _dismiss(head),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
