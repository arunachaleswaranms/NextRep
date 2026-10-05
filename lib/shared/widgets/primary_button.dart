import 'package:flutter/material.dart';

/// Full-width call to action. While [busy] it is disabled and shows a
/// spinner, so a double tap cannot submit twice.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        // The button keeps its name while busy, so a screen reader still
        // knows what is in progress.
        ? Semantics(
            label: label,
            child: const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        : Text(label),
  );
}
