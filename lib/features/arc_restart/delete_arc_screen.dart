import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/time/clock.dart';
import '../../domain/history/arc_history_service.dart';
import '../../shared/widgets/winter_background.dart';
import '../summary/arc_removal.dart';
import 'restart_labels.dart';
import 'typed_word_field.dart';

/// "Delete your previous Arc?" (ARC_CONTROL_SPEC § 9.11): the separate,
/// optional deletion of one finished arc (completed, or ended early), with
/// its own typed word, **DELETE**.
///
/// Opened right after a restart that chose "Delete my old Arc…"
/// ([afterRestart]), or from a finished arc's summary. It lists what will
/// be lost, in numbers (zero shown as 0), and offers a backup first.
/// Nothing is deleted until **Delete** is pressed with DELETE typed; Keep
/// it, Back and leaving the app keep the arc, and no intention to delete is
/// stored (D4). The deletion is one transaction, by this arc's id, and
/// only while it is still finished (D5): the active arc is never touched.
class DeleteArcScreen extends ConsumerStatefulWidget {
  const DeleteArcScreen({
    super.key,
    required this.sessionId,
    this.afterRestart = false,
  });

  /// The finished arc to delete.
  final int sessionId;

  /// Opened right after a restart: Back and Keep it go to Today.
  final bool afterRestart;

  @override
  ConsumerState<DeleteArcScreen> createState() => _DeleteArcScreenState();
}

class _DeleteArcScreenState extends ConsumerState<DeleteArcScreen> {
  final _typed = TextEditingController();

  /// What is shown: read once, so nothing on screen changes (or fails to
  /// load) while the deletion runs.
  ArcHistoryCard? _card;
  bool _loadFailed = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _wordMatches => typedWordMatches(_typed.text, DeleteArcCopy.word);

  Future<void> _load() async {
    try {
      final card = await ref
          .read(arcHistoryServiceProvider)
          .card(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _card = card;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _delete() async {
    if (_busy || _card == null || !_wordMatches) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await ref
        .read(arcRemovalProvider)
        .deleteFinishedArc(widget.sessionId);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(DeleteArcCopy.deleted)));
        context.go(widget.afterRestart ? AppRoutes.today : value);
      case ActionFailure():
        // One transaction: nothing was removed, both arcs are unchanged.
        setState(() {
          _busy = false;
          _failed = true;
        });
    }
  }

  /// Keep it, Back: the arc stays (to Today after a restart, otherwise
  /// back to its summary).
  void _keep() {
    if (_busy) return;
    if (!widget.afterRestart && context.canPop()) {
      context.pop();
    } else {
      context.go(
        widget.afterRestart ? AppRoutes.today : AppRoutes.arc(widget.sessionId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final title = widget.afterRestart
        ? DeleteArcCopy.titleAfterRestart
        : DeleteArcCopy.titleFromSummary;
    return PopScope(
      canPop: !_busy && !widget.afterRestart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _keep();
      },
      child: Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: _busy ? null : _keep)),
        body: WinterBackground(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                WinterSpacing.lg,
                WinterSpacing.md,
                WinterSpacing.lg,
                WinterSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScreenHeading(title),
                      card == null
                          ? _loading(context)
                          : _content(context, card),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!_loadFailed) {
      return const Padding(
        padding: EdgeInsets.all(WinterSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(DeleteArcCopy.loadFailed, style: text.bodyLarge),
        const SizedBox(height: WinterSpacing.md),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _load,
          child: const Text(DeleteArcCopy.retry),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _keep,
          child: const Text(DeleteArcCopy.keep),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, ArcHistoryCard card) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final session = card.session;
    final summary = card.summary;
    final today = ref.watch(clockProvider).today();
    final finished = session.status.isFinished;
    final action = widget.afterRestart
        ? DeleteArcCopy.actionAfterRestart
        : DeleteArcCopy.actionFromSummary;
    final losses = [
      DeleteArcCopy.progress(summary.daysElapsed, summary.totalXp),
      DeleteArcCopy.achievements(summary.achievementsUnlocked),
      DeleteArcCopy.reflections(card.reflectionCount),
      DeleteArcCopy.journey,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.afterRestart) ...[
          Text(DeleteArcCopy.afterRestartNote, style: text.bodyLarge),
          const SizedBox(height: WinterSpacing.md),
        ],
        Text(DeleteArcCopy.arcLine(session, today), style: text.titleMedium),
        Text(DeleteArcCopy.status(session), style: text.bodyLarge),
        const SizedBox(height: WinterSpacing.md),
        Text(DeleteArcCopy.removes, style: text.bodyLarge),
        const SizedBox(height: WinterSpacing.xs),
        // A list, read item by item with its numbers (§ 9.11).
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final loss in losses) _Bullet(loss)],
          ),
        ),
        Text(DeleteArcCopy.insights, style: text.bodyMedium),
        Text(DeleteArcCopy.othersKept, style: text.bodyMedium),
        const SizedBox(height: WinterSpacing.md),
        Text(
          DeleteArcCopy.noUndo,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: WinterSpacing.xs),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : () => context.push(AppRoutes.dataBackup),
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text(DeleteArcCopy.exportFirst),
        ),
        const SizedBox(height: WinterSpacing.lg),
        TypedWordField(
          key: const ValueKey('delete-word'),
          label: DeleteArcCopy.fieldLabel,
          word: DeleteArcCopy.word,
          controller: _typed,
          enabled: !_busy && finished,
          onSubmitted: _delete,
        ),
        const SizedBox(height: WinterSpacing.md),
        if (_failed) ...[
          Semantics(
            liveRegion: true,
            child: Text(DeleteArcCopy.failed, style: text.bodyMedium),
          ),
          const SizedBox(height: WinterSpacing.sm),
        ],
        Semantics(
          label: _wordMatches || _busy
              ? null
              : DeleteArcCopy.actionDisabled(action),
          excludeSemantics: !_wordMatches && !_busy,
          button: !_wordMatches && !_busy,
          enabled: _wordMatches && !_busy,
          child: FilledButton.icon(
            key: const ValueKey('delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              // Dark text on the danger colour: readable (4.5:1 and more),
              // and the action is named in words, not by colour alone.
              foregroundColor: colors.background,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _wordMatches && !_busy && finished ? _delete : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.delete_forever_rounded),
            // Labelled in words, not by colour alone.
            label: Text(_failed ? DeleteArcCopy.retry : action),
          ),
        ),
        const SizedBox(height: WinterSpacing.sm),
        TextButton(
          key: const ValueKey('delete-keep'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : _keep,
          child: const Text(DeleteArcCopy.keep),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text('•  ', style: style)),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
