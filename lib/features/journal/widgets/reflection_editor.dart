import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../core/errors/action_result.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/reflection/daily_reflection.dart';
import '../../../shared/formatting/failure_messages.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/winter_card.dart';
import 'mood_selector.dart';

/// Today's quick reflection: a mood and two one-line answers, about 20
/// seconds. Starts from [initial] when editing a saved reflection.
///
/// [onSave] persists the draft; the domain validates it again, so this
/// widget's checks are only for immediate feedback.
class ReflectionEditor extends StatefulWidget {
  const ReflectionEditor({
    super.key,
    required this.onSave,
    this.initial,
    this.onCancel,
  });

  final DailyReflection? initial;
  final Future<ActionResult<Object?>> Function(ReflectionDraft draft) onSave;

  /// Shown as "Cancel" when editing a saved reflection.
  final VoidCallback? onCancel;

  @override
  State<ReflectionEditor> createState() => _ReflectionEditorState();
}

/// One-line answers that wrap: Enter submits (or moves to the next field)
/// rather than adding a line break, and pasted line breaks become spaces.
const _singleLine = TextInputType.text;
final _noLineBreaks = [
  FilteringTextInputFormatter.deny(RegExp(r'[\r\n]+'), replacementString: ' '),
];

class _ReflectionEditorState extends State<ReflectionEditor> {
  late Mood? _mood = widget.initial?.mood;
  late final _win = TextEditingController(text: widget.initial?.win);
  late final _improvement = TextEditingController(
    text: widget.initial?.improvement,
  );
  final _improvementFocus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _win.dispose();
    _improvement.dispose();
    _improvementFocus.dispose();
    super.dispose();
  }

  ReflectionDraft get _draft => ReflectionDraft(
    mood: _mood,
    win: _win.text,
    improvement: _improvement.text,
  );

  Future<void> _save() async {
    if (_saving) return;
    try {
      ReflectionRules.validate(_draft);
    } on DomainFailure catch (failure) {
      setState(() => _error = userMessageFor(failure));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.onSave(_draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result case ActionFailure(:final failure)) {
        _error = userMessageFor(failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How did today feel?', style: text.titleMedium),
          const SizedBox(height: WinterSpacing.sm),
          MoodSelector(
            selected: _mood,
            enabled: !_saving,
            onChanged: (mood) => setState(() {
              _mood = mood;
              _error = null;
            }),
          ),
          const SizedBox(height: WinterSpacing.md),
          TextField(
            controller: _win,
            enabled: !_saving,
            maxLength: ReflectionRules.maxTextLength,
            minLines: 1,
            maxLines: 3,
            keyboardType: _singleLine,
            inputFormatters: _noLineBreaks,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _improvementFocus.requestFocus(),
            onChanged: (_) => _clearError(),
            decoration: const InputDecoration(
              labelText: 'One win today',
              hintText: 'Something that went well',
            ),
          ),
          const SizedBox(height: WinterSpacing.xs),
          TextField(
            controller: _improvement,
            focusNode: _improvementFocus,
            enabled: !_saving,
            maxLength: ReflectionRules.maxTextLength,
            minLines: 1,
            maxLines: 3,
            keyboardType: _singleLine,
            inputFormatters: _noLineBreaks,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => _clearError(),
            decoration: const InputDecoration(
              labelText: 'One thing to improve',
              hintText: 'Small and specific',
            ),
          ),
          // Announced as soon as it appears.
          Semantics(
            liveRegion: true,
            child: AnimatedSize(
              duration: context.motion.standard,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: colors.warning,
                          ),
                          const SizedBox(width: WinterSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: text.bodyMedium?.copyWith(
                                color: colors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: WinterSpacing.sm),
          PrimaryButton(
            label: widget.initial == null
                ? 'Save Reflection'
                : 'Update Reflection',
            busy: _saving,
            onPressed: _save,
          ),
          if (widget.onCancel != null)
            TextButton(
              onPressed: _saving ? null : widget.onCancel,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }
}
