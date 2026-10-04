import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/reflection/daily_reflection.dart';
import '../../domain/reflection/reflection_service.dart';
import '../../shared/feedback/haptics.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'journal_controller.dart';
import 'widgets/reflection_editor.dart';
import 'widgets/reflection_entry_card.dart';

/// The Journal: nightly reflections, newest first. Without [sessionId] it
/// is the active arc's tab, where today's reflection can be written; with
/// one, that arc's Journal from Arc History, read-only.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key, this.sessionId});

  final int? sessionId;

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  late final AppLifecycleListener _lifecycle;

  /// Whether today's saved reflection is open for editing.
  bool _editing = false;

  bool get _historical => widget.sessionId != null;

  @override
  void initState() {
    super.initState();
    // A new day may have started while backgrounded.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!_historical) {
          unawaited(ref.read(journalControllerProvider.notifier).refresh());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<ActionResult<ReflectionSave>> _save(ReflectionDraft draft) async {
    final result = await ref
        .read(journalControllerProvider.notifier)
        .save(draft);
    if (!mounted) return result;
    if (result case ActionSuccess(:final value)) {
      unawaited(Haptics.reflectionSaved());
      setState(() => _editing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              value.created ? 'Reflection saved' : 'Reflection updated',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final journal = switch (widget.sessionId) {
      null => ref.watch(journalControllerProvider),
      final id => ref.watch(arcJournalProvider(id)),
    };
    final body = switch (journal) {
      AsyncData(:final value) => _content(context, value),
      AsyncError(:final error, :final stackTrace) => FailureView(
        failure: toAppFailure(error, stackTrace),
        onRetry: () => switch (widget.sessionId) {
          null => ref.invalidate(journalControllerProvider),
          final id => ref.invalidate(arcJournalProvider(id)),
        },
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Scaffold(
      appBar: _historical
          ? AppBar(
              title: const Text('Journal'),
              backgroundColor: Colors.transparent,
            )
          : null,
      extendBodyBehindAppBar: _historical,
      body: WinterBackground(child: SafeArea(child: body)),
    );
  }

  Widget _content(BuildContext context, JournalView view) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final today = view.todayEntry;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            WinterSpacing.sm,
            WinterSpacing.md,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_historical)
                  Row(
                    children: [
                      const SizedBox(width: WinterSpacing.xs),
                      Expanded(
                        child: Text(
                          'JOURNAL',
                          style: text.labelLarge?.copyWith(
                            color: colors.accentSecondary,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reminders',
                        onPressed: () => context.push(AppRoutes.reminders),
                        icon: const Icon(Icons.notifications_none_rounded),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WinterSpacing.xs,
                  ),
                  child: Text(
                    _historical
                        ? arcHeading(view.session)
                        : 'A minute to look back on the day. '
                              'Skipping a night is fine.',
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(height: WinterSpacing.md),
                if (view.canWriteToday) ...[
                  _SectionLabel('TODAY · DAY ${view.dayNumberOf(view.today)}'),
                  if (today != null && !_editing)
                    ReflectionEntryCard(
                      reflection: today,
                      dayNumber: view.dayNumberOf(today.date),
                      trailing: TextButton(
                        onPressed: () => setState(() => _editing = true),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text(
                          'Edit',
                          semanticsLabel: "Edit today's reflection",
                        ),
                      ),
                    )
                  else
                    ReflectionEditor(
                      key: ValueKey(today?.updatedAt),
                      initial: today,
                      onSave: _save,
                      onCancel: today == null
                          ? null
                          : () => setState(() => _editing = false),
                    ),
                  const SizedBox(height: WinterSpacing.lg),
                ] else if (!_historical) ...[
                  _Note(
                    'This Winter Arc is complete. Its Journal is read-only.',
                  ),
                  const SizedBox(height: WinterSpacing.lg),
                ],
                if (view.past.isNotEmpty || _historical)
                  _SectionLabel(_historical ? 'REFLECTIONS' : 'PAST'),
                if (view.past.isEmpty)
                  _Note(
                    _historical
                        ? 'No reflections were saved in this arc.'
                        : 'Past reflections will gather here.',
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            0,
            WinterSpacing.md,
            WinterSpacing.xl,
          ),
          sliver: SliverList.builder(
            itemCount: view.past.length,
            itemBuilder: (context, index) {
              final reflection = view.past[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                child: ReflectionEntryCard(
                  reflection: reflection,
                  dayNumber: view.dayNumberOf(reflection.date),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinterSpacing.xs,
      0,
      WinterSpacing.xs,
      WinterSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: context.winter.textSecondary, letterSpacing: 2),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.xs),
    child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
  );
}
