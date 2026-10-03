import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scrolls the first scrollable on screen (Today's list) until [finder] is
/// built and visible, as a user would to reach a lower habit.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
