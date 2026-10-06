import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/history/arc_history_service.dart';
import '../../../domain/winter_arc/winter_arc_session.dart';
import '../../../shared/formatting/arc_labels.dart';
import '../../../shared/widgets/winter_card.dart';
import '../arc_history_controller.dart';

/// One arc in Arc History: dates, status and results. Its numbers load
/// when the tile is built, so only visible arcs are computed.
class ArcHistoryTile extends ConsumerWidget {
  const ArcHistoryTile({super.key, required this.session, required this.onTap});

  final WinterArcSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(arcHistoryCardProvider(session.id));
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final active = session.status == WinterArcStatus.active;
    final range = arcDateRange(session);
    final status = active ? 'ACTIVE' : 'COMPLETED';
    final stats = card.value;
    final kind = arcKindTitle(session);
    final joined = session.joinedLate
        ? 'Joined Day ${session.joinDayNumber}'
        : null;
    return Semantics(
      button: true,
      label: _label(kind, range, status, joined, stats),
      onTap: onTap,
      excludeSemantics: true,
      child: WinterCard(
        highlighted: active,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind.toUpperCase(),
                    style: text.labelLarge?.copyWith(
                      color: colors.accentSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                _StatusChip(label: status, active: active),
              ],
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(range, style: text.titleLarge),
            if (joined != null)
              Text(
                joined,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            const SizedBox(height: WinterSpacing.sm),
            switch (card) {
              AsyncValue(:final value?) => _Stats(card: value),
              AsyncError() => Row(
                children: [
                  Expanded(
                    child: Text(
                      "Couldn't load this arc's results.",
                      style: text.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(arcHistoryCardProvider(session.id)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
              _ => const SizedBox(
                height: WinterSpacing.xxl,
                child: Center(
                  child: LinearProgressIndicator(semanticsLabel: 'Loading'),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }

  static String _label(
    String kind,
    String range,
    String status,
    String? joined,
    ArcHistoryCard? card,
  ) {
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = ['$kind, $range, ${status.toLowerCase()}', ?joined];
    if (card != null) {
      final s = card.summary;
      parts.addAll([
        'Level ${s.level.level}, ${s.totalXp} XP',
        '${count(s.perfectDays, 'Perfect Day', 'Perfect Days')}, '
            'best streak ${s.bestPerfectStreak}',
        'Consistency ${s.consistencyPercent} percent',
        '${s.achievementsUnlocked} of ${s.achievementsTotal} achievements, '
            '${count(card.reflectionCount, 'reflection', 'reflections')}',
      ]);
    }
    return parts.join('. ');
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final tint = active ? colors.accentSecondary : colors.celebration;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WinterSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WinterRadii.pill),
        border: Border.all(color: tint.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.play_arrow_rounded : Icons.flag_rounded,
            size: 14,
            color: tint,
          ),
          const SizedBox(width: WinterSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tint, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.card});

  final ArcHistoryCard card;

  @override
  Widget build(BuildContext context) {
    final summary = card.summary;
    final items = [
      ('Level ${summary.level.level}', '${summary.totalXp} XP'),
      ('${summary.perfectDays}', 'Perfect Days'),
      ('${summary.consistencyPercent}%', 'Consistency'),
      ('${summary.bestPerfectStreak}', 'Best streak'),
      (
        '${summary.achievementsUnlocked}/${summary.achievementsTotal}',
        'Achievements',
      ),
      ('${card.reflectionCount}', 'Reflections'),
    ];
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: WinterSpacing.md,
      runSpacing: WinterSpacing.sm,
      children: [
        for (final (value, label) in items)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: text.titleMedium),
                Text(label, style: text.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
