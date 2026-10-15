import 'dart:io';

import 'package:drift/drift.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';

/// Focus Guard's native background check, as far as the database sees it:
/// its one write, the day's claim, taken verbatim from
/// `android/.../focusguard/FocusGuardStore.kt` so tests run what ships.
const focusGuardKotlinDir =
    'android/app/src/main/kotlin/com/nextrep/nextrep/focusguard';

String focusGuardKotlin(String file) =>
    File('$focusGuardKotlinDir/$file').readAsStringSync();

/// The claim statement with [packages] placeholders expanded.
String workerClaimSql(int packages) {
  final match = RegExp(
    r'"""\s*(UPDATE focus_guard_preferences SET last_nudged_on = \?.*?)"""',
    dotAll: true,
  ).firstMatch(focusGuardKotlin('FocusGuardStore.kt'));
  if (match == null) throw StateError('claim SQL not found in Kotlin source');
  return match
      .group(1)!
      .replaceAll(r'$placeholders', List.filled(packages, '?').join(','));
}

/// Runs the worker's claim for [today] against [db], as a check that
/// measured [packages] over [budget] minutes would. Returns whether it
/// claimed the day, i.e. whether that check would post its nudge.
Future<bool> workerClaim(
  AppDatabase db,
  LocalDate today, {
  required int budget,
  required List<String> packages,
}) async {
  final changed = await db.customUpdate(
    workerClaimSql(packages.length),
    variables: [
      Variable.withString(today.toIsoString()),
      Variable.withInt(budget),
      Variable.withString(today.toIsoString()),
      Variable.withString(today.addDays(1).toIsoString()),
      Variable.withInt(packages.length),
      for (final p in packages) Variable.withString(p),
    ],
    updates: {db.focusGuardPrefs},
  );
  return changed == 1;
}
