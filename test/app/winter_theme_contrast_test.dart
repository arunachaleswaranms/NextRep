import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/app/theme/winter_tokens.dart';
import 'package:nextrep/shared/widgets/primary_button.dart';

/// Phase 12D review D1: the app-wide primary (filled) button's text must
/// reach WCAG AA's 4.5:1 on its background, in every interactive state,
/// on every screen that uses the theme. Sizes, shape and the disabled
/// colours stay as they were.

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final theme = buildWinterTheme();
  final colors = theme.extension<WinterColors>()!;
  final style = theme.filledButtonTheme.style!;

  test('enabled text is at least 4.5:1 at rest, hovered, focused and '
      'pressed', () {
    for (final states in <Set<WidgetState>>[
      {},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      final background = style.backgroundColor!.resolve(states)!;
      final foreground = style.foregroundColor!.resolve(states)!;
      final overlay = style.overlayColor?.resolve(states);
      final shown = overlay == null
          ? background
          : Color.alphaBlend(overlay, background);
      expect(
        _contrast(foreground, shown),
        greaterThanOrEqualTo(4.5),
        reason: 'states $states',
      );
    }
    expect(style.backgroundColor!.resolve({}), colors.accent);
    expect(
      _contrast(style.foregroundColor!.resolve({})!, colors.accent),
      greaterThan(6.5),
    );
  });

  test('disabled colours, size, shape and type are unchanged', () {
    const disabled = {WidgetState.disabled};
    expect(style.backgroundColor!.resolve(disabled), colors.surfaceElevated);
    expect(style.foregroundColor!.resolve(disabled), colors.textSecondary);
    expect(style.minimumSize!.resolve({}), const Size.fromHeight(56));
    expect(
      style.shape!.resolve({}),
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WinterRadii.button),
      ),
    );
    final label = style.textStyle!.resolve({})!;
    expect(label.fontSize, 16);
    expect(label.fontWeight, FontWeight.w700);
  });

  testWidgets('rendered primary buttons pass the text-contrast guideline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              backgroundColor: colors.background,
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PrimaryButton(label: 'Start Challenge', onPressed: () {}),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                  const SizedBox(height: 16),
                  const PrimaryButton(label: 'Unavailable', onPressed: null),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(
        tester
            .getSize(find.widgetWithText(FilledButton, 'Start Challenge'))
            .height,
        greaterThanOrEqualTo(56),
      );
    }
    handle.dispose();
  });
}
