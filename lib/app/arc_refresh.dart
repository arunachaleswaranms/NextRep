import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped after any persisted change to the active arc, so screens that
/// show derived history (e.g. Journey) re-read it.
final arcRefreshProvider = NotifierProvider<ArcRefresh, int>(ArcRefresh.new);

class ArcRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}
