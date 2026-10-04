import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped after any persisted change to the active arc, so screens that
/// show derived history (e.g. Journey) re-read it.
final arcRefreshProvider = NotifierProvider<ArcRefresh, int>(ArcRefresh.new);

class ArcRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

/// Bumped after an arc is deleted (a completed arc, or a cancelled setup),
/// so lists across arcs (Arc History, Insights) re-read.
final arcsChangedProvider = NotifierProvider<ArcsChanged, int>(ArcsChanged.new);

class ArcsChanged extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}
