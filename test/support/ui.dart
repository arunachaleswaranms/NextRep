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

/// Taps [finder], scrolling the first scrollable to it if it isn't on
/// screen yet (Habit Setup's actions follow the list at large text).
Future<void> tapShown(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Phase 12D: starts the Arc from Habit Setup the only way the app offers:
/// Review & Start → Review Setup's Continue to Start → Confirm & Start's
/// "Confirm & Start Challenge" (or "Confirm & Join Season").
Future<void> startFromSetup(WidgetTester tester) async {
  await tapShown(tester, find.text('Review & Start'));
  await confirmFromReview(tester);
}

/// From Review Setup: Continue to Start, then the confirm button.
Future<void> confirmFromReview(WidgetTester tester) async {
  await tapShown(tester, find.text('Continue to Start'));
  await tapShown(tester, find.textContaining(RegExp(r'^Confirm & ')));
}

/// Phase 12D: from the saved-setup hub (where the app opens with a setup),
/// Continue Editing opens Habit Setup.
Future<void> continueEditing(WidgetTester tester) =>
    tapShown(tester, find.text('Continue Editing'));
