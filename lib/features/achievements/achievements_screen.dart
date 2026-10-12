import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/achievement/achievement.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'achievements_controller.dart';
import 'widgets/achievement_card.dart';

/// The achievement collection: every badge, locked or unlocked, grouped by
/// category under a heading each. Without
/// [sessionId] it shows the active arc's; with one, that arc's from Arc
/// History, read-only.
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key, this.sessionId});

  final int? sessionId;

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  @override
  void initState() {
    super.initState();
    // Self-heal any unlock a failed run missed before showing the board.
    // History is read-only, so only the home arc's board is reconciled.
    if (widget.sessionId == null) {
      unawaited(ref.read(achievementSyncProvider).run());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AchievementBoard?> board = switch (widget.sessionId) {
      null => ref.watch(achievementBoardProvider),
      final id => ref.watch(arcAchievementBoardProvider(id)),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch (board) {
            AsyncValue(hasError: false, :final value?) => _content(
              context,
              value,
            ),
            AsyncValue(hasError: false, hasValue: true) => const EmptyStateView(
              icon: Icons.emoji_events_outlined,
              title: 'Start your Winter Arc to collect achievements.',
            ),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => switch (widget.sessionId) {
                null => ref.invalidate(achievementBoardProvider),
                final id => ref.invalidate(arcAchievementBoardProvider(id)),
              },
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AchievementBoard board) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.md,
            WinterSpacing.lg,
            WinterSpacing.md,
          ),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              label:
                  '${board.unlockedCount} of ${board.total} achievements '
                  'unlocked',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COLLECTION',
                    style: text.labelLarge?.copyWith(
                      color: colors.accentSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(
                    '${board.unlockedCount} of ${board.total} unlocked',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(WinterRadii.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: board.unlockedCount / board.total),
                      duration: context.motion.celebration,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        color: colors.celebration,
                      ),
                    ),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  Text(
                    'Collectibles for showing up. They never change your XP.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final (category, entries) in board.groups) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              WinterSpacing.lg,
              WinterSpacing.md,
              WinterSpacing.lg,
              WinterSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: _CategoryHeading(category: category, entries: entries),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.lg),
            sliver: SliverList.builder(
              itemCount: (entries.length + 1) ~/ 2,
              itemBuilder: (context, row) => _CardRow(
                left: entries[row * 2],
                right: row * 2 + 1 < entries.length
                    ? entries[row * 2 + 1]
                    : null,
                board: board,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: WinterSpacing.xl)),
      ],
    );
  }
}

/// A category's heading: its name and how much of it is unlocked.
class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({required this.category, required this.entries});

  final AchievementCategory category;
  final List<AchievementStatus> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final unlocked = entries.where((e) => e.unlocked).length;
    return Semantics(
      header: true,
      label: '${category.label}, $unlocked of ${entries.length} unlocked',
      excludeSemantics: true,
      child: Wrap(
        spacing: WinterSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(
            category.label.toUpperCase(),
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 2,
            ),
          ),
          Text(
            '$unlocked / ${entries.length}',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Two cards side by side, equal height.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.left,
    required this.right,
    required this.board,
  });

  final AchievementStatus left;
  final AchievementStatus? right;
  final AchievementBoard board;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AchievementCard(status: left, board: board),
          ),
          const SizedBox(width: WinterSpacing.sm),
          Expanded(
            child: switch (right) {
              final right? => AchievementCard(status: right, board: board),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    ),
  );
}
