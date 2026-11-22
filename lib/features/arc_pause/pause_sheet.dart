import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/winter_arc/arc_clock_guard.dart';
import '../../domain/winter_arc/arc_pause.dart';
import '../../shared/widgets/primary_button.dart';
import '../focus_guard/focus_guard_entry.dart';
import 'pause_actions.dart';
import 'pause_labels.dart';

/// How the Pause sheet closed.
enum PauseSheetResult {
  /// The pause is stored, from tomorrow.
  scheduled,

  /// The user chose "Focus Guard settings"; nothing was stored. The caller
  /// opens the settings once the sheet is gone.
  openFocusGuard,
}

/// "Pause your Arc" (spec § 9.6). Reads its dates from the service when it
/// opens, and again when the date changes while it is open or a request is
/// refused, so it never schedules a date it didn't show. Not now, Back and
/// dismissing write nothing.
class PauseArcSheet extends ConsumerStatefulWidget {
  const PauseArcSheet({super.key, required this.sessionId});

  /// The arc the user was looking at.
  final int sessionId;

  /// Null when it was dismissed or Not now was chosen.
  static Future<PauseSheetResult?> show(BuildContext context, int sessionId) =>
      showModalBottomSheet<PauseSheetResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => PauseArcSheet(sessionId: sessionId),
      );

  @override
  ConsumerState<PauseArcSheet> createState() => _PauseArcSheetState();
}

class _PauseArcSheetState extends ConsumerState<PauseArcSheet> {
  PausePreview? _preview;
  bool _loadFailed = false;
  bool _busy = false;

  /// "Couldn't pause. Nothing was changed." after a storage failure.
  bool _failed = false;

  /// The dates were re-read because the date changed.
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
      final preview = await service.pausePreview(widget.sessionId);
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

  Future<void> _pause() async {
    final preview = _preview;
    if (_busy || preview == null || !preview.canPause) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await runPauseAction(
      ref,
      'pause',
      (service) => service.pause(
        sessionId: widget.sessionId,
        frozenFrom: preview.frozenFrom,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        Navigator.of(context).pop(PauseSheetResult.scheduled);
      case ActionFailure(failure: DomainFailure(:final rule))
          when rule == DomainRule.pauseDateChanged ||
              rule == DomainRule.pauseUnavailable ||
              rule == DomainRule.clockBehindHistory:
        // Refused, nothing stored: show the sheet as things are now (new
        // dates, the clock-guard refusal, or why it isn't available).
        await _load(dateChanged: rule == DomainRule.pauseDateChanged);
        if (mounted) setState(() => _busy = false);
      case ActionFailure():
        // Any other failure (storage, a rolled-back change): say so.
        await _load();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Midnight while the sheet is open: re-read before anything is pressed.
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
              child: Text(PauseCopy.sheetTitle, style: text.headlineSmall),
            ),
            const SizedBox(height: WinterSpacing.md),
            if (preview == null && _loadFailed) ...[
              Text(PauseCopy.pauseFailed, style: text.bodyLarge),
              const SizedBox(height: WinterSpacing.md),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
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
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text(PauseCopy.notNow),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, PausePreview preview) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final note = text.bodyMedium?.copyWith(color: colors.accentSecondary);
    if (preview.blocker != null) {
      return [Text(PauseCopy.unavailable, style: text.bodyLarge)];
    }
    if (preview.guard case final ClockGuardBehind behind) {
      return [
        Text(
          PauseCopy.clockBehind(behind),
          semanticsLabel: PauseCopy.clockBehindSpoken(behind),
          style: text.bodyLarge,
        ),
      ];
    }
    final focusGuard = ref.watch(focusGuardEntryProvider).value;
    final showFocusGuard = focusGuard != null && focusGuard.supported;
    return [
      if (_dateChanged) ...[
        Text(PauseCopy.dateChanged, style: note),
        const SizedBox(height: WinterSpacing.sm),
      ],
      Text(
        PauseCopy.intro(preview.frozenFrom, preview.today),
        semanticsLabel: PauseCopy.introSpoken(preview.frozenFrom),
        style: text.bodyLarge,
      ),
      const SizedBox(height: WinterSpacing.md),
      // A list, so a screen reader announces its items as such.
      Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Bullet(PauseCopy.todayCounts(preview.todayDayNumber!)),
            const _Bullet(PauseCopy.neverMissed),
            _Bullet(PauseCopy.continuesOn(preview.nextDayNumber!)),
            _Bullet(
              showFocusGuard
                  ? '${PauseCopy.remindersPause} ${PauseCopy.focusGuardOwn}'
                  : PauseCopy.remindersPause,
            ),
          ],
        ),
      ),
      if (showFocusGuard)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy
                ? null
                : () =>
                      Navigator.of(context)
                          .pop(PauseSheetResult.openFocusGuard),
            icon: const Icon(Icons.shield_outlined),
            label: const Text(PauseCopy.focusGuardLink),
          ),
        ),
      const SizedBox(height: WinterSpacing.md),
      if (_failed) ...[
        Text(PauseCopy.pauseFailed, style: text.bodyMedium),
        const SizedBox(height: WinterSpacing.sm),
      ],
      PrimaryButton(
        label: _failed ? PauseCopy.retry : PauseCopy.pauseAction,
        busy: _busy,
        onPressed: _pause,
      ),
    ];
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
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
