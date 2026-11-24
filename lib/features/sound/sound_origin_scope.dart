import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_restart.dart';
import '../../domain/feedback/sound_origin.dart';

/// The [SoundOrigin] of a screen that makes sounds (Today's completions,
/// Sound & Feedback's previews): active only while that screen is the one
/// the user sees (Phase 12G review correction G-R1).
///
/// A request takes [soundOrigin] when the user acts and passes it to the
/// feedback engine, which drops the request if the origin was cancelled by
/// the time the setting has been read. The origin is cancelled as soon as
/// any of these stops being true:
///
/// * the router's top page is at [soundLocation]: not another tab, not a
///   page pushed over this one, and this one not popped;
/// * tickers are enabled here: false in an indexed-stack tab that isn't
///   shown, and under an opaque page. `mounted` alone isn't enough: a tab
///   stays mounted while another tab is shown;
/// * the app is in the foreground ([AppLifecycleState.resumed]);
/// * the app epoch is unchanged (a restore rebuilds every screen);
/// * the screen is mounted;
///
/// and whenever the screen calls [renewSoundOrigin] (Today: its Arc
/// changed). Once eligible again the screen gets a new origin, so a request
/// made before can never become valid again by coming back.
mixin SoundOriginScope<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The router path at which this screen is what the user sees.
  String get soundLocation;

  SoundOrigin _origin = SoundOrigin.cancelled();
  late final AppLifecycleListener _soundLifecycle;
  GoRouterDelegate? _routerDelegate;
  bool _foreground = true;
  bool _tickersOn = false;
  bool _atLocation = false;

  /// The origin for a request made now.
  SoundOrigin get soundOrigin => _origin;

  /// Drops every request of this screen that hasn't started yet. Later
  /// requests get a new origin if the screen is still eligible.
  void renewSoundOrigin() {
    _origin.cancel();
    _sync();
  }

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _soundLifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _sync();
      },
    );
    ref.listenManual(appEpochProvider, (_, _) => renewSoundOrigin());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersOn = TickerMode.valuesOf(context).enabled;
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (!identical(delegate, _routerDelegate)) {
      _routerDelegate?.removeListener(_locationChanged);
      _routerDelegate = delegate?..addListener(_locationChanged);
    }
    _locationChanged();
  }

  @override
  void dispose() {
    _origin.cancel();
    _routerDelegate?.removeListener(_locationChanged);
    _soundLifecycle.dispose();
    super.dispose();
  }

  void _locationChanged() {
    final delegate = _routerDelegate;
    // The top page: a page pushed over the shell, or the shown tab's.
    // (`currentConfiguration.uri` stays the base location under a `push`.)
    // Without a router (a screen pumped on its own) only the other
    // conditions apply.
    _atLocation =
        delegate == null ||
        delegate.currentConfiguration.lastOrNull?.matchedLocation ==
            soundLocation;
    _sync();
  }

  void _sync() {
    if (!(mounted && _foreground && _tickersOn && _atLocation)) {
      _origin.cancel();
    } else if (!_origin.isActive) {
      _origin = SoundOrigin();
    }
  }
}
