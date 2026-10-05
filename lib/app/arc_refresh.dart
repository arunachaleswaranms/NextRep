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

/// Bumped when the local date changes while the app stays open (see
/// [DayChangeTicker]), so screens that show "today" without a habit change
/// to trigger them (the Journal) re-read.
final dayChangedProvider = NotifierProvider<DayChanged, int>(DayChanged.new);

class DayChanged extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}
