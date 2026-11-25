import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../domain/winter_arc/arc_clock_guard.dart';
import '../../domain/winter_arc/arc_restart.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import '../history/arc_history_controller.dart';
import 'restart_actions.dart';
import 'restart_labels.dart';
import 'typed_word_field.dart';

/// "Restart with this setup" (ARC_CONTROL_SPEC § 9.9), and the success
/// screen of § 9.10 once the restart has committed with Keep selected.
///
/// Reads what it shows from `ArcRestartService.preview` when it opens, and
/// again when the date changes while it is open or a request is refused,
/// so it never restarts on a date (or with a last day) it didn't show.
/// Nothing is written until **Restart Arc** is pressed with RESTART typed;
/// Cancel, Back and leaving write nothing and discard the typed text.
///
/// Choosing "Delete my old Arc…" deletes nothing here: after the restart
/// has committed, the separate typed-DELETE screen opens (spec § 7, D2,
/// D3). No intention to delete is stored anywhere (D4).
class RestartScreen extends ConsumerStatefulWidget {
  const RestartScreen({super.key, required this.sessionId});

  /// The arc the user was looking at.
  final int sessionId;

  @override
  ConsumerState<RestartScreen> createState() => _RestartScreenState();
}

class _RestartScreenState extends ConsumerState<RestartScreen> {
  final _typed = TextEditingController();
  RestartPreview? _preview;
  bool _loadFailed = false;
  bool _busy = false;

  /// "Couldn't restart. Nothing was changed." after a storage failure.
  bool _failed = false;

  /// The details were re-read because the date changed.
  bool _dateChanged = false;

  /// The restart was refused as unavailable (the arc changed elsewhere).
  bool _unavailable = false;

  /// Keep (false, the default) or Delete it… (true).
  bool _deleteOld = false;

  /// Set once the restart has committed (Keep): the success screen.
  RestartOutcome? _outcome;

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

  bool get _wordMatches => typedWordMatches(_typed.text, RestartCopy.word);

  Future<void> _load({bool dateChanged = false}) async {
    if (_outcome != null) return; // done: nothing to re-read
    final service = ref.read(arcRestartServiceProvider);
    final previous = _preview;
    try {
      final preview = await service.preview(widget.sessionId);
      if (!mounted || _outcome != null) return;
      setState(() {
        _preview = preview;
        _loadFailed = false;
        _dateChanged =
            dateChanged ||
            (previous != null && previous.today != preview.today);
      });
      if (preview.blocker
          case RestartBlocker.over || RestartBlocker.notActive) {
        // The arc completed at midnight (or changed elsewhere): let the
        // router take the app to where it now belongs (spec § 9.9: "the
        // screen closes to the completed Arc's summary").
        await _republish();
      }
    } catch (_) {
      // Never leave details on screen that could not be re-read.
      if (mounted) {
        setState(() {
          _preview = null;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _republish() async {
    try {
      await ref.read(arcResolutionProvider.notifier).reconcile();
    } catch (error, stackTrace) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'arcs');
    }
  }

  Future<void> _restart() async {
    final preview = _preview;
    final closedOn = preview?.closedOn;
    if (_busy || preview == null || closedOn == null || !_wordMatches) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _unavailable = false;
    });
    final deleteOld = _deleteOld;
    final result = await runRestart(
      ref,
      sessionId: widget.sessionId,
      shownOn: preview.today,
      shownClosedOn: closedOn,
    );
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value):
        if (deleteOld) {
          // The separate, optional step (spec § 7). The old arc stays
          // unless it is confirmed there.
          context.go(AppRoutes.deleteArc(value.ended.id, afterRestart: true));
          return;
        }
        // The success heading is a live region: it is announced.
        setState(() {
          _busy = false;
          _outcome = value;
        });
      case ActionFailure(failure: DomainFailure(:final rule))
          when rule == DomainRule.restartDateChanged ||
              rule == DomainRule.clockBehindHistory:
        // Refused, nothing stored: show the screen as things are now.
        await _load(dateChanged: rule == DomainRule.restartDateChanged);
        if (mounted) setState(() => _busy = false);
      case ActionFailure(failure: DomainFailure(:final rule))
          when rule == DomainRule.arcCompleted ||
              rule == DomainRule.restartUnavailable:
        await _load();
        await _republish();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _unavailable = true;
        });
      case ActionFailure():
        // A storage failure (or a rolled-back change): nothing was
        // changed; say so and offer Retry.
        await _load();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _failed = true;
        });
    }
  }

  void _close() {
    if (_outcome != null) {
      context.go(AppRoutes.today);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.today);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Midnight while the screen is open: re-read before anything is
    // pressed.
    ref.listen(dayChangedProvider, (_, _) => _load(dateChanged: true));
    final preview = _preview;
    final outcome = _outcome;
    final title = outcome != null
        ? RestartCopy.started
        : preview == null
        ? RestartCopy.loadingTitle
        : RestartCopy.title(preview.session);
    return PopScope(
      // While saving nothing may leave; after the restart, Back goes to
      // Today (spec § 9.10).
      canPop: !_busy && outcome == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && outcome != null) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: outcome == null
              ? null
              : IconButton(
                  tooltip: RestartCopy.goToToday,
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
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
                  child: outcome != null
                      ? _Success(outcome: outcome, onToday: _close)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ScreenHeading(title),
                            _confirmation(context, preview),
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

  Widget _confirmation(BuildContext context, RestartPreview? preview) {
    final text = Theme.of(context).textTheme;
    if (preview == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _loadFailed
            ? [
                Text(
                  RestartCopy.failed,
                  style: text.bodyLarge,
                  semanticsLabel: RestartCopy.failed,
                ),
                const SizedBox(height: WinterSpacing.md),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _load,
                  child: const Text(RestartCopy.retry),
                ),
              ]
            : const [
                Padding(
                  padding: EdgeInsets.all(WinterSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._details(context, preview),
        const SizedBox(height: WinterSpacing.md),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : _close,
          child: const Text(RestartCopy.cancel),
        ),
      ],
    );
  }

  List<Widget> _details(BuildContext context, RestartPreview preview) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final note = text.bodyMedium?.copyWith(color: colors.accentSecondary);
    final session = preview.session;
    if (preview.guard case final ClockGuardBehind behind) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(
            RestartCopy.clockBehind(behind),
            semanticsLabel: RestartCopy.clockBehindSpoken(behind),
            style: text.bodyLarge,
          ),
        ),
      ];
    }
    final closedDay = preview.closedDayNumber;
    if (!preview.canRestart || closedDay == null) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(RestartCopy.unavailable, style: text.bodyLarge),
        ),
      ];
    }
    final habits = preview.habits.length;
    final on = preview.habitsOn;
    final open = session.hasOpenFreeze ? session.freezes.last : null;
    return [
      if (_dateChanged) ...[
        Semantics(
          liveRegion: true,
          child: Text(RestartCopy.dateChanged, style: note),
        ),
        const SizedBox(height: WinterSpacing.sm),
      ],
      if (session.isSeasonal) ...[
        Text(RestartCopy.seasonalIntro(closedDay), style: text.bodyLarge),
        const SizedBox(height: WinterSpacing.xs),
        Text(RestartCopy.seasonalHabits(habits, on: on), style: text.bodyLarge),
      ] else
        Text(RestartCopy.intro(habits, on: on), style: text.bodyLarge),
      const SizedBox(height: WinterSpacing.xs),
      Text(
        RestartCopy.dates(preview.today, preview.newLastDay),
        semanticsLabel: RestartCopy.datesSpoken(
          preview.today,
          preview.newLastDay,
        ),
        style: text.bodyMedium,
      ),
      const SizedBox(height: WinterSpacing.md),
      if (!session.isSeasonal)
        Text(
          RestartCopy.endsAt(closedDay, session.lengthInDays),
          style: text.bodyLarge,
        ),
      Text(RestartCopy.notCompleted, style: text.bodyLarge),
      Text(RestartCopy.ownProgress, style: text.bodyLarge),
      if (preview.isLastDay) ...[
        const SizedBox(height: WinterSpacing.sm),
        Text(RestartCopy.lastDay, style: note),
      ],
      if (open != null) ...[
        const SizedBox(height: WinterSpacing.sm),
        Text(
          preview.today.isBefore(open.frozenFrom)
              ? RestartCopy.scheduledPauseRemoved
              : RestartCopy.pauseEnds,
          style: note,
        ),
      ],
      const SizedBox(height: WinterSpacing.lg),
      // "Your old Arc": a labelled radio group (§ 9.9 accessibility).
      Semantics(
        container: true,
        label: RestartCopy.oldArcHeading,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: ExcludeSemantics(
                child: Text(
                  RestartCopy.oldArcHeading.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: colors.accentSecondary,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            RadioGroup<bool>(
              groupValue: _deleteOld,
              onChanged: (value) {
                if (_busy || value == null) return;
                setState(() => _deleteOld = value);
              },
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    key: ValueKey('restart-keep'),
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: Text(RestartCopy.keep),
                  ),
                  RadioListTile<bool>(
                    key: ValueKey('restart-delete'),
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(RestartCopy.delete),
                    subtitle: Text(RestartCopy.deleteNote),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: WinterSpacing.md),
      TypedWordField(
        key: const ValueKey('restart-word'),
        label: RestartCopy.fieldLabel,
        word: RestartCopy.word,
        controller: _typed,
        enabled: !_busy,
        onSubmitted: _restart,
      ),
      const SizedBox(height: WinterSpacing.md),
      if (_failed || _unavailable) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            _unavailable ? RestartCopy.unavailable : RestartCopy.failed,
            style: text.bodyMedium,
          ),
        ),
        const SizedBox(height: WinterSpacing.sm),
      ],
      Semantics(
        label: _wordMatches || _busy
            ? null
            : RestartCopy.actionDisabled(session),
        excludeSemantics: !_wordMatches && !_busy,
        button: !_wordMatches && !_busy,
        enabled: _wordMatches && !_busy,
        child: PrimaryButton(
          key: const ValueKey('restart-confirm'),
          label: _failed ? RestartCopy.retry : RestartCopy.action(session),
          busy: _busy,
          onPressed: _wordMatches ? _restart : null,
        ),
      ),
    ];
  }
}

/// "Your new Arc has started" (spec § 9.10).
class _Success extends ConsumerWidget {
  const _Success({required this.outcome, required this.onToday});

  final RestartOutcome outcome;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final ended = outcome.ended;
    final today = outcome.started.startDate;
    final xp = ref.watch(arcHistoryCardProvider(ended.id)).value?.summary;
    final closedDay = ended.dayNumberOf(ended.closedOn!) ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.check_circle_rounded,
                color: colors.accentSecondary,
              ),
            ),
            const SizedBox(width: WinterSpacing.sm),
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: Text(RestartCopy.started, style: text.titleLarge),
              ),
            ),
          ],
        ),
        const SizedBox(height: WinterSpacing.xs),
        Text(
          RestartCopy.startedOn(today),
          semanticsLabel: RestartCopy.startedOnSpoken(today),
          style: text.bodyLarge,
        ),
        const SizedBox(height: WinterSpacing.lg),
        Text(RestartCopy.previousInHistory, style: text.bodyMedium),
        Text(
          RestartCopy.previous(closedDay, ended.lengthInDays, xp?.totalXp),
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: WinterSpacing.lg),
        PrimaryButton(label: RestartCopy.goToToday, onPressed: onToday),
        const SizedBox(height: WinterSpacing.sm),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => context.push(AppRoutes.arc(ended.id)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(child: Text(RestartCopy.viewPrevious)),
              const ExcludeSemantics(child: Icon(Icons.chevron_right_rounded)),
            ],
          ),
        ),
      ],
    );
  }
}
