import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/winter_arc/arc_pause.dart';
import '../../shared/widgets/primary_button.dart';
import 'pause_actions.dart';
import 'pause_labels.dart';

/// "Resume your Arc?" (spec § 9.8). Shows exactly what Resume would store
/// (the service's own preview of the resumed arc), re-reads it when the
/// date changes while it is open, and closes with `true` only once the
/// resume is stored: nothing is shown as resumed before that. Not yet,
/// Back and dismissing leave the Arc paused.
class ResumeArcSheet extends ConsumerStatefulWidget {
  const ResumeArcSheet({super.key, required this.sessionId});

  final int sessionId;

  static Future<bool> show(BuildContext context, int sessionId) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => ResumeArcSheet(sessionId: sessionId),
      ) ??
      false;

  @override
  ConsumerState<ResumeArcSheet> createState() => _ResumeArcSheetState();
}

class _ResumeArcSheetState extends ConsumerState<ResumeArcSheet> {
  ResumePreview? _preview;
  bool _loadFailed = false;
  bool _busy = false;
  bool _failed = false;
  bool _dateChanged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool dateChanged = false}) async {
    final service = ref.read(arcPauseServiceProvider);
    final previous = _preview;
    try {
      final preview = await service.resumePreview(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadFailed = false;
        _dateChanged =
            dateChanged ||
            (previous != null && previous.today != preview.today);
      });
    } catch (_) {
      // Never leave dates on screen that could not be re-read: show the
      // error and Retry instead.
      if (mounted) {
        setState(() {
          _preview = null;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _resume() async {
    final preview = _preview;
    // Single-fire: a second tap while saving does nothing.
    if (_busy || preview == null || !preview.canResume) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await runPauseAction(
      ref,
      'resume',
      (service) =>
          service.resume(sessionId: widget.sessionId, on: preview.today),
    );
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        Navigator.of(context).pop(true);
      case ActionFailure(
        failure: DomainFailure(rule: DomainRule.resumeDateChanged),
      ):
        await _load(dateChanged: true);
        if (mounted) setState(() => _busy = false);
      case ActionFailure(failure: DomainFailure(rule: DomainRule.notPaused)):
        // Not paused today (the date moved): the re-read sheet says so.
        await _load();
        if (mounted) setState(() => _busy = false);
      case ActionFailure():
        // Nothing was stored: the Arc is still paused.
        await _load();
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = true;
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dayChangedProvider, (_, _) => _load(dateChanged: true));
    final text = Theme.of(context).textTheme;
    final preview = _preview;
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
            Semantics(
              header: true,
              container: true,
              child: Text(ResumeCopy.title, style: text.headlineSmall),
            ),
            const SizedBox(height: WinterSpacing.md),
            if (preview == null && _loadFailed) ...[
              Text(ResumeCopy.failed, style: text.bodyLarge),
              const SizedBox(height: WinterSpacing.md),
              OutlinedButton(
                onPressed: _load,
                child: const Text(PauseCopy.retry),
              ),
            ] else if (preview == null)
              const Padding(
                padding: EdgeInsets.all(WinterSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._body(context, preview),
            const SizedBox(height: WinterSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text(ResumeCopy.notYet),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ResumePreview preview) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final day = preview.dayNumber;
    final lastDay = preview.lastDay;
    if (!preview.canResume || day == null || lastDay == null) {
      return [Text(ResumeCopy.notPaused, style: text.bodyLarge)];
    }
    final total = preview.session.lengthInDays;
    final earlier = preview.totalPausedDays - preview.pausedDays;
    return [
      if (_dateChanged) ...[
        Text(
          PauseCopy.dateChanged,
          style: text.bodyMedium?.copyWith(color: colors.accentSecondary),
        ),
        const SizedBox(height: WinterSpacing.sm),
      ],
      Text(
        ResumeCopy.becomes(preview.today, day, total),
        semanticsLabel: ResumeCopy.becomesSpoken(preview.today, day, total),
        style: text.bodyLarge,
      ),
      const SizedBox(height: WinterSpacing.xs),
      Text(
        ResumeCopy.lastDay(lastDay, preview.today),
        semanticsLabel: ResumeCopy.lastDaySpoken(lastDay),
        style: text.bodyLarge,
      ),
      const SizedBox(height: WinterSpacing.xs),
      Text(ResumeCopy.pausedFor(preview.pausedDays), style: text.bodyLarge),
      if (earlier > 0)
        Text(
          ResumeCopy.totalPaused(preview.totalPausedDays),
          style: text.bodyMedium,
        ),
      const SizedBox(height: WinterSpacing.lg),
      if (_failed) ...[
        Text(ResumeCopy.failed, style: text.bodyMedium),
        const SizedBox(height: WinterSpacing.sm),
      ],
      PrimaryButton(
        label: _failed ? PauseCopy.retry : ResumeCopy.resumeAction,
        busy: _busy,
        onPressed: _resume,
      ),
    ];
  }
}
