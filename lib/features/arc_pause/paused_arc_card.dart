import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/time/local_date.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_card.dart';
import 'pause_labels.dart';

/// Today while the Arc is paused (spec § 9.7): reads only. No habit, no
/// Minimum Day, no editing, no reflection for a paused date. History stays
/// one tap away.
///
/// [position] is today's [ArcPaused] position. A pause that is still open
/// offers Resume; a date the clock moved back into an earlier, closed pause
/// shows when the Arc continues instead, and no Resume (it was resumed).
class PausedArcCard extends StatelessWidget {
  const PausedArcCard({
    super.key,
    required this.position,
    required this.today,
    required this.onResume,
  });

  final ArcPaused position;
  final LocalDate today;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final since = position.pausedSince;
    final resumesOn = position.resumesOn;
    final days = since.daysUntil(today);
    final secondary = text.bodyMedium?.copyWith(color: colors.textPrimary);
    final links = [
      _Link(PausedCopy.journey, () => context.go(AppRoutes.journey)),
      _Link(PausedCopy.journal, () => context.go(AppRoutes.journal)),
      _Link(PausedCopy.history, () => context.go(AppRoutes.history)),
    ];
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.ac_unit_rounded,
                  color: colors.accentSecondary,
                ),
              ),
              const SizedBox(width: WinterSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text(PausedCopy.heading, style: text.titleLarge),
                ),
              ),
            ],
          ),
          const SizedBox(height: WinterSpacing.xs),
          if (resumesOn == null)
            Text(
              PausedCopy.since(since, days, today),
              semanticsLabel: PausedCopy.sinceSpoken(since, days),
              style: text.bodyMedium,
            )
          else
            Text(
              PausedCopy.closed(since, resumesOn, today),
              semanticsLabel: PausedCopy.closedSpoken(since, resumesOn),
              style: text.bodyMedium,
            ),
          const SizedBox(height: WinterSpacing.md),
          Text(
            PausedCopy.stoppedAfter(position.lastDayNumber, position.totalDays),
            style: secondary,
          ),
          if (resumesOn == null)
            Text(
              PausedCopy.becomes(position.lastDayNumber + 1),
              style: secondary,
            )
          else
            Text(
              PausedCopy.continuesOn(resumesOn, today),
              semanticsLabel: PausedCopy.continuesOnSpoken(resumesOn),
              style: secondary,
            ),
          Text(PausedCopy.noCount, style: secondary),
          if (resumesOn == null) ...[
            const SizedBox(height: WinterSpacing.lg),
            PrimaryButton(label: PausedCopy.resumeAction, onPressed: onResume),
          ],
          const SizedBox(height: WinterSpacing.md),
          // Side by side at normal text; one link per line above 1.3× text
          // (spec § 9.7 "Large text", the rule of the other v1.3 screens).
          if (MediaQuery.textScalerOf(context).scale(1) > 1.3)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: links,
            )
          else
            Wrap(spacing: WinterSpacing.sm, children: links),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        const ExcludeSemantics(child: Icon(Icons.chevron_right_rounded)),
      ],
    ),
  );
}

/// "Pause starts tomorrow. Today still counts. · Cancel pause" (spec
/// § 9.6), on Today while a pause is scheduled.
class PauseScheduledBanner extends StatelessWidget {
  const PauseScheduledBanner({
    super.key,
    required this.frozenFrom,
    required this.today,
    required this.onCancel,
    this.busy = false,
  });

  final LocalDate frozenFrom;
  final LocalDate today;
  final VoidCallback onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final tomorrow = frozenFrom == today.addDays(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WinterSpacing.md,
        WinterSpacing.md,
        WinterSpacing.sm,
        WinterSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accentSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(WinterRadii.card),
        border: Border.all(
          color: colors.accentSecondary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.ac_unit_rounded,
                  color: colors.accentSecondary,
                ),
              ),
              const SizedBox(width: WinterSpacing.md),
              Expanded(
                child: Text(
                  tomorrow
                      ? PauseCopy.bannerTomorrow
                      : PauseCopy.bannerOn(frozenFrom, today),
                  semanticsLabel: tomorrow
                      ? null
                      : 'Pause starts ${pauseDateSpoken(frozenFrom)}. Today '
                            'still counts.',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy ? null : onCancel,
              child: const Text(PauseCopy.cancelAction),
            ),
          ),
        ],
      ),
    );
  }
}
