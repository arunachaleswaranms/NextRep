import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'arc_history_controller.dart';
import 'widgets/arc_history_tile.dart';

/// Arc History: every started arc, newest first. The History tab while an
/// arc runs; a full-screen page from the summary otherwise.
///
/// The active arc opens Today. A completed arc opens its read-only overview
/// by id, so it always shows that arc and never a newer one.
class ArcHistoryScreen extends ConsumerWidget {
  const ArcHistoryScreen({super.key, this.standalone = false});

  /// A full-screen page with a back button rather than a tab.
  final bool standalone;

  void _open(BuildContext context, WinterArcSession session) {
    if (session.status == WinterArcStatus.active) {
      context.go(AppRoutes.today);
    } else {
      context.push(AppRoutes.arc(session.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(arcHistoryProvider);
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: standalone
          ? AppBar(
              title: const Text('Arc History'),
              backgroundColor: Colors.transparent,
            )
          : null,
      extendBodyBehindAppBar: standalone,
      body: WinterBackground(
        child: SafeArea(
          child: switch (sessions) {
            AsyncData(:final value) => CustomScrollView(
              slivers: [
                if (!standalone)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      WinterSpacing.lg,
                      WinterSpacing.md,
                      WinterSpacing.lg,
                      WinterSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ARC HISTORY',
                            style: text.labelLarge?.copyWith(
                              color: colors.accentSecondary,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: WinterSpacing.xs),
                          Text(
                            'Every climb you have made, newest first.',
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (value.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No arcs yet.')),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    WinterSpacing.md,
                    WinterSpacing.sm,
                    WinterSpacing.md,
                    WinterSpacing.xl,
                  ),
                  sliver: SliverList.builder(
                    itemCount: value.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                      child: ArcHistoryTile(
                        key: ValueKey(value[index].id),
                        session: value[index],
                        onTap: () => _open(context, value[index]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(arcHistoryProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}
