import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_status.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../shared/formatting/failure_messages.dart';
import '../summary/arc_removal.dart';

/// "Cancel setup", the one way to delete a saved setup, from Habit Setup
/// and from the saved-setup hub: the existing confirmation dialog, then
/// [ArcRemoval.cancelSetup], which deletes only the arc in setup and its
/// habits (completed and ended arcs are untouched) and says where to go.
/// Nothing is deleted unless "Cancel Setup" is chosen in the dialog.
Future<void> confirmCancelSetup(BuildContext context, WidgetRef ref) async {
  final hasHistory = ref.read(arcResolutionProvider)?.latestCompleted != null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel this setup?'),
      content: Text(
        hasHistory
            ? 'Your previous completed Arcs will remain safe.'
            : 'Your habit choices will be cleared. You can start again '
                  'whenever you are ready.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep Setup'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.winter.danger,
            // Dark text on the danger colour (about 6.7:1, as on the
            // Delete Arc screen); light text was 2.7:1 (Phase 12H).
            foregroundColor: context.winter.background,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Cancel Setup'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final result = await ref.read(arcRemovalProvider).cancelSetup();
  if (!context.mounted) return;
  switch (result) {
    case ActionSuccess(:final value):
      context.go(value);
    case ActionFailure(:final failure):
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
  }
}
