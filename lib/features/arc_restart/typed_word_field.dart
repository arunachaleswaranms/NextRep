import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// The typed-confirmation field of Restart and Delete (spec §§ 6.6, 9.9,
/// 9.11): its instruction ("Type RESTART to confirm") is a wrapping line
/// above the field, so it is never cut short at large text, and it is also
/// the field's accessible label. The keyboard opens in capitals; no
/// autocorrect or suggestions can change the word.
class TypedWordField extends StatelessWidget {
  const TypedWordField({
    super.key,
    required this.label,
    required this.word,
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  /// "Type RESTART to confirm".
  final String label;

  /// The word to type, shown as the empty field's hint.
  final String word;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: WinterSpacing.xs),
      Semantics(
        label: label,
        child: TextField(
          controller: controller,
          enabled: enabled,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            hintText: word,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    ],
  );
}

/// A screen's heading as the first line of its scrolling column (spec
/// §§ 9.9–9.11: "everything in one scrolling column"; focus starts on the
/// heading), so it wraps at large text instead of being cut short in a
/// one-line app bar.
class ScreenHeading extends StatelessWidget {
  const ScreenHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WinterSpacing.md),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
    ),
  );
}
