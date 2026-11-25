import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/arc_restart/restart_labels.dart';

import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12H (brief § 8, ARC_CONTROL_SPEC §§ 9.9, 9.11): on the Restart
/// and Delete Arc screens a screen reader reaches every consequence before
/// the typed-word field and the confirm control, the disabled control says
/// why it is disabled, and it is named in words. The order is read from
/// the semantics tree in **traversal order** (what TalkBack follows), at 1×
/// and 2× text. All data synthetic.

final _day1 = LocalDate(2028, 1, 5);
LocalDate _d(int n) => _day1.addDays(n - 1);

/// Every labelled semantics node, in traversal order.
List<String> _spoken(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode node) {
    final label = node.label.replaceAll('\n', ' ').trim();
    if (label.isNotEmpty) out.add(label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  var root = tester.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return out;
}

int _first(List<String> spoken, Pattern text, String why) {
  final i = spoken.indexWhere((s) => s.contains(text));
  expect(i, isNot(-1), reason: '$why: "$text" is announced\n$spoken');
  return i;
}

Future<void> _show(
  WidgetTester tester,
  double text,
  String route,
  TestApp app,
) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(reviewApp(app.db, app.clock, route));
  await tester.pumpAndSettle();
  await clearCelebrations(tester);
}

void main() {
  for (final text in [1.0, 2.0]) {
    testWidgets('Restart at $text×: the consequences come before the field '
        'and the button; the disabled button says why', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2028, 1, 5)));
      addTearDown(app.db.close);
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(9));
      at(app, _d(10), hour: 20);
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(11));
      await _show(tester, text, AppRoutes.restartArc(arc.id), app);
      final spoken = _spoken(tester);
      final session = (await app.sessions.sessionById(arc.id))!;
      final consequences = [
        _first(spoken, 'ends at Day', 'Restart'),
        _first(spoken, RestartCopy.notCompleted, 'Restart'),
        _first(spoken, RestartCopy.scheduledPauseRemoved, 'Restart'),
      ];
      final field = _first(spoken, RestartCopy.fieldLabel, 'Restart');
      final button = _first(
        spoken,
        RestartCopy.actionDisabled(session),
        'Restart (disabled, with its reason)',
      );
      for (final c in consequences) {
        expect(c, lessThan(field), reason: 'consequence before the field');
        expect(c, lessThan(button), reason: 'consequence before the button');
      }
      expect(
        RestartCopy.actionDisabled(session),
        contains('Type RESTART'),
        reason: 'the reason is in the label',
      );
      handle.dispose();
    });

    testWidgets('Delete Arc at $text×: every loss is announced before the '
        'field and the button; the disabled button says why', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2028, 1, 5)));
      addTearDown(app.db.close);
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(6));
      at(app, _d(7), hour: 12);
      await restartNow(app, arc.id);
      await _show(
        tester,
        text,
        AppRoutes.deleteArc(arc.id, afterRestart: true),
        app,
      );
      final spoken = _spoken(tester);
      final losses = [
        _first(spoken, DeleteArcCopy.removes, 'Delete'),
        _first(spoken, 'challenge days and', 'Delete'),
        _first(spoken, DeleteArcCopy.journey, 'Delete'),
        _first(spoken, DeleteArcCopy.noUndo, 'Delete'),
      ];
      final field = _first(spoken, DeleteArcCopy.fieldLabel, 'Delete');
      final button = _first(
        spoken,
        DeleteArcCopy.actionDisabled(DeleteArcCopy.actionAfterRestart),
        'Delete (disabled, with its reason)',
      );
      for (final l in losses) {
        expect(l, lessThan(field), reason: 'loss before the field');
        expect(l, lessThan(button), reason: 'loss before the button');
      }
      handle.dispose();
    });
  }
}
