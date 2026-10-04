import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/features/celebration/celebration_cards.dart';

/// Lets queued celebration cards (Perfect Day, achievements) time out. They
/// float over the top of the screen and take taps, so a test about to tap
/// something waits for them like a user would.
Future<void> clearCelebrations(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    if (find.byType(CelebrationCard).evaluate().isEmpty) return;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }
}

/// Scrolls the first scrollable on screen (Today's list) until [finder] is
/// built and visible, as a user would to reach a lower habit, once no
/// celebration covers the screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
