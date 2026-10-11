import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../data/share_gateway.dart';
import '../../domain/achievement/achievement.dart';
import '../../domain/progress/day_summary.dart';
import 'share_card_capture.dart';
import 'share_card_data.dart';
import 'widgets/share_cards.dart';

/// One share card ready to export: the card and what goes with its PNG.
final class ShareCardContent {
  const ShareCardContent({
    required this.card,
    required this.fileName,
    required this.text,
    required this.semanticsLabel,
  });

  ShareCardContent.today(TodayShareCardData data)
    : this(
        card: TodayShareCard(data: data),
        fileName: data.fileName,
        text: data.shareText,
        semanticsLabel: data.semanticsLabel,
      );

  ShareCardContent.arc(ArcShareCardData data)
    : this(
        card: ArcShareCard(data: data),
        fileName: data.fileName,
        text: data.shareText,
        semanticsLabel: data.semanticsLabel,
      );

  ShareCardContent.achievement(AchievementShareCardData data)
    : this(
        card: AchievementShareCard(data: data),
        fileName: data.fileName,
        text: data.shareText,
        semanticsLabel: data.semanticsLabel,
      );

  final Widget card;
  final String fileName;
  final String text;

  /// What the card shows, for screen readers.
  final String semanticsLabel;
}

/// Shows exactly the image that will be shared, and shares it through the
/// system share sheet only when the user taps Share.
///
/// Sharing writes nothing to the database and earns nothing; closing the
/// sheet without sharing is not an error. Privacy switches (Today's
/// Progress only) apply to this preview alone and are never saved.
class SharePreviewScreen extends ConsumerStatefulWidget {
  const SharePreviewScreen({
    super.key,
    required this.title,
    required this.content,
    this.privacyControls = false,
  });

  final String title;

  /// The card for the current privacy choices.
  final ShareCardContent Function(SharePrivacyOptions privacy) content;

  /// Shows the habit names / XP and level / streak switches.
  final bool privacyControls;

  static Future<void> _open(BuildContext context, SharePreviewScreen screen) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen),
      );

  /// Previews today's progress from the persisted [summary].
  static Future<void> today(BuildContext context, DaySummary summary) => _open(
    context,
    SharePreviewScreen(
      title: "Share Today's Progress",
      privacyControls: true,
      content: (privacy) => ShareCardContent.today(
        TodayShareCardData.fromSummary(summary, privacy: privacy),
      ),
    ),
  );

  /// Previews the current arc's goals from the persisted [summary].
  static Future<void> arc(BuildContext context, DaySummary summary) {
    final content = ShareCardContent.arc(ArcShareCardData.fromSummary(summary));
    return _open(
      context,
      SharePreviewScreen(title: 'Share My Arc', content: (_) => content),
    );
  }

  /// Previews an unlocked achievement; does nothing for a locked one.
  static Future<void> achievement(
    BuildContext context,
    AchievementStatus status,
    AchievementBoard board,
  ) async {
    final data = AchievementShareCardData.of(status, board);
    if (data == null) return;
    final content = ShareCardContent.achievement(data);
    await _open(
      context,
      SharePreviewScreen(title: 'Share Achievement', content: (_) => content),
    );
  }

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  var _privacy = const SharePrivacyOptions();
  var _sharing = false;

  /// Captures the card on screen and opens the share sheet, once at a
  /// time: taps while a share is being prepared or the sheet is open do
  /// nothing.
  Future<void> _share(ShareCardContent content) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final gateway = ref.read(shareGatewayProvider);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await ShareCardCapture.png(boundary);
      await gateway.share(
        ShareFile.png(bytes: png, name: content.fileName),
        text: content.text,
        origin: _shareOrigin(),
      );
    } catch (error, stackTrace) {
      // The failure only; never the image or what it shows.
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'share');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text("Couldn't open the share sheet.")),
          );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Where the iPad share popover points: the Share button.
  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content = widget.content(_privacy);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), leading: const CloseButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.md,
            WinterSpacing.lg,
            WinterSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Preview(
                cardKey: _cardKey,
                semanticsLabel: content.semanticsLabel,
                card: content.card,
              ),
              const SizedBox(height: WinterSpacing.sm),
              Text(
                'This is the image that will be shared. NextRep never '
                'shares anything by itself.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              if (widget.privacyControls) ...[
                const SizedBox(height: WinterSpacing.md),
                _PrivacySwitches(
                  privacy: _privacy,
                  onChanged: (privacy) => setState(() => _privacy = privacy),
                ),
              ],
              const SizedBox(height: WinterSpacing.lg),
              FilledButton.icon(
                key: _shareButtonKey,
                onPressed: _sharing ? null : () => _share(content),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
              const SizedBox(height: WinterSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card scaled to fit the screen, revealed once with a short fade and
/// a slight scale (immediately under reduced motion). The reveal wraps the
/// card's [RepaintBoundary], so the export is always the still card at
/// full size.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.cardKey,
    required this.semanticsLabel,
    required this.card,
  });

  final GlobalKey cardKey;
  final String semanticsLabel;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final canvas = ShareCardCapture.canvas;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          math.min(constraints.maxWidth, canvas.width),
          maxHeight * canvas.aspectRatio,
        );
        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: context.motion.standard,
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
            ),
            child: Semantics(
              image: true,
              label: semanticsLabel,
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(WinterRadii.button),
                  border: Border.all(color: colors.glassBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WinterRadii.button),
                  child: SizedBox(
                    width: width,
                    height: width / canvas.aspectRatio,
                    child: FittedBox(
                      child: RepaintBoundary(key: cardKey, child: card),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrivacySwitches extends StatelessWidget {
  const _PrivacySwitches({required this.privacy, required this.onChanged});

  final SharePrivacyOptions privacy;
  final ValueChanged<SharePrivacyOptions> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: const Text('Show habit names'),
        value: privacy.habitNames,
        onChanged: (on) => onChanged(privacy.copyWith(habitNames: on)),
      ),
      SwitchListTile(
        title: const Text('Show XP & level'),
        value: privacy.xpAndLevel,
        onChanged: (on) => onChanged(privacy.copyWith(xpAndLevel: on)),
      ),
      SwitchListTile(
        title: const Text('Show streak'),
        value: privacy.streak,
        onChanged: (on) => onChanged(privacy.copyWith(streak: on)),
      ),
    ],
  );
}
