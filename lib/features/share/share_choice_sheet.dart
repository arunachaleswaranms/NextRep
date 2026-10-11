import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// The cards Today can share.
enum ShareChoice { todayProgress, myArc }

/// Asks which card to share from Today. Pops the choice, or null if the
/// sheet was closed; it never shares anything itself.
class ShareChoiceSheet extends StatelessWidget {
  const ShareChoiceSheet({super.key});

  static Future<ShareChoice?> show(BuildContext context) =>
      showModalBottomSheet<ShareChoice>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => const ShareChoiceSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WinterSpacing.lg,
          0,
          WinterSpacing.lg,
          WinterSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share your Arc', style: text.headlineSmall),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              "Pick a card. You'll see it before anything is shared.",
              style: text.bodyMedium,
            ),
            const SizedBox(height: WinterSpacing.md),
            _Option(
              icon: Icons.today_rounded,
              accent: colors.accentSecondary,
              title: "Today's Progress",
              subtitle: "Today's habits, with level and streak if you like",
              onTap: () => Navigator.of(context).pop(ShareChoice.todayProgress),
            ),
            const SizedBox(height: WinterSpacing.sm),
            _Option(
              icon: Icons.flag_rounded,
              accent: colors.celebration,
              title: 'My Arc',
              subtitle: 'The habits and goals you committed to',
              onTap: () => Navigator.of(context).pop(ShareChoice.myArc),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Material(
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WinterRadii.card),
        side: BorderSide(color: colors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WinterSpacing.md,
          vertical: WinterSpacing.xs,
        ),
        leading: Icon(icon, color: accent),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}
