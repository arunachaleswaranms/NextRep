import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../shared/widgets/primary_button.dart';
import '../setup_labels.dart';

/// A filled action that may be unavailable: then it is disabled, its
/// reason is written under it, and its accessible name includes the
/// reason ("Start Challenge, unavailable. Add a habit to start.").
class StartButton extends StatelessWidget {
  const StartButton({
    super.key,
    required this.label,
    required this.blocked,
    required this.onPressed,
    this.busy = false,
  });

  final String label;

  /// Why it's unavailable, or null.
  final String? blocked;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final reason = blocked;
    final button = PrimaryButton(
      label: label,
      busy: busy,
      onPressed: reason == null ? onPressed : null,
    );
    if (reason == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: false,
          label: SetupLabels.unavailable(label, reason),
          excludeSemantics: true,
          child: button,
        ),
        Padding(
          padding: const EdgeInsets.only(top: WinterSpacing.xs),
          child: ExcludeSemantics(
            child: Text(
              reason,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
