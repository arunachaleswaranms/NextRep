import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../domain/winter_arc/current_arc_service.dart';
import '../features/celebration/celebration_overlay.dart';
import '../shared/widgets/failure_view.dart';
import '../shared/widgets/loading_view.dart';
import '../shared/widgets/winter_background.dart';
import 'app_restart.dart';
import 'arc_refresh.dart';
import 'arc_status.dart';
import 'day_change.dart';
import 'dependencies.dart';
import 'router/app_router.dart';
import 'theme/winter_theme.dart';

class NextRepApp extends ConsumerWidget {
  const NextRepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epoch = ref.watch(appEpochProvider);
    final boot = ref.watch(bootLocationProvider);
    // While the boot location is (re)computed nothing is routed: after a
    // restore the old router and its screens are gone before the new ones
    // read the restored data.
    if (boot.isLoading) {
      return const _StatusApp(child: LoadingView());
    }
    return switch (boot) {
      AsyncData(:final value) => _RoutedApp(
        key: ValueKey(epoch),
        initialLocation: value,
      ),
      AsyncError(:final error, :final stackTrace) => _StatusApp(
        child: _BootFailure(failure: toAppFailure(error, stackTrace)),
      ),
      _ => const _StatusApp(child: LoadingView()),
    };
  }
}

/// Owns the router for the app's lifetime. The boot location is only used
/// as the initial location; later navigation is driven by the features, by
/// the arc resolution (a close-out redirects to the summary), and by tapped
/// reminders.
///
/// It also keeps the pending reminders in line with the arcs: after launch,
/// on resume, and whenever the active arc changes (started, closed, or a
/// new one). While the app is in the foreground it moves every screen to
/// the new day at local midnight.
class _RoutedApp extends ConsumerStatefulWidget {
  const _RoutedApp({super.key, required this.initialLocation});

  final String initialLocation;

  @override
  ConsumerState<_RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends ConsumerState<_RoutedApp> {
  late final _resolution = ValueNotifier<ArcResolution?>(
    ref.read(arcResolutionProvider),
  );
  late final GoRouter _router = buildAppRouter(
    initialLocation: widget.initialLocation,
    resolution: _resolution,
  );
  late final AppLifecycleListener _lifecycle;
  late final DayChangeTicker _dayChange = DayChangeTicker(
    clock: ref.read(clockProvider),
    onDayChanged: _onDayChanged,
  );
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String?>? _taps;

  @override
  void initState() {
    super.initState();
    ref.listenManual(arcResolutionProvider, (previous, next) {
      _resolution.value = next;
      if (previous?.active?.id != next?.active?.id) _syncReminders();
    });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _dayChange.start();
        unawaited(_onResume());
      },
      onPause: _dayChange.stop,
    );
    _taps = ref.read(reminderTapsProvider).listen(_openReminder);
    _dayChange.start();
    _syncReminders();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice());
  }

  /// Shows the message left by the action that restarted the app (e.g. a
  /// restore), once.
  void _showNotice() {
    if (!mounted) return;
    final notice = ref.read(appNoticeProvider.notifier).take();
    if (notice == null) return;
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  void dispose() {
    unawaited(_taps?.cancel());
    _dayChange.stop();
    _lifecycle.dispose();
    _router.dispose();
    _resolution.dispose();
    super.dispose();
  }

  /// Closes out an arc that ended while the app was in the background, on
  /// any screen, then re-plans reminders (the date or time zone may have
  /// changed).
  Future<void> _onResume() async {
    try {
      await ref.read(arcResolutionProvider.notifier).reconcile();
    } catch (error, stackTrace) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'resume');
    }
    if (mounted) await _syncReminders();
  }

  /// Local midnight passed with the app open: close out an arc that has
  /// just ended, then have every screen re-read the new day.
  Future<void> _onDayChanged() async {
    await _onResume();
    if (!mounted) return;
    ref.read(arcRefreshProvider.notifier).changed();
    ref.read(dayChangedProvider.notifier).changed();
  }

  /// A reminder was tapped while the app was running. Its destination is
  /// resolved against the arcs as they are now, so a stale reminder never
  /// opens a writable screen of an arc that has closed.
  Future<void> _openReminder(String? payload) async {
    try {
      final resolution = await ref
          .read(arcResolutionProvider.notifier)
          .reconcile();
      if (!mounted) return;
      _router.go(AppRoutes.forReminder(payload, resolution));
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'reminders',
      );
    }
  }

  /// Best effort: reminders are secondary, so a failure is reported and
  /// the next launch, resume or change tries again.
  Future<void> _syncReminders() async {
    try {
      await ref.read(reminderServiceProvider).reconcile();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'reminders',
      );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'NextRep',
    debugShowCheckedModeBanner: false,
    theme: buildWinterTheme(),
    routerConfig: _router,
    scaffoldMessengerKey: _messenger,
    // Perfect Day, level-up and achievement cards, one at a time, above
    // every route.
    builder: (context, child) => CelebrationOverlay(child: child!),
  );
}

class _StatusApp extends StatelessWidget {
  const _StatusApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NextRep',
    debugShowCheckedModeBanner: false,
    theme: buildWinterTheme(),
    home: Scaffold(body: WinterBackground(child: child)),
  );
}

class _BootFailure extends ConsumerStatefulWidget {
  const _BootFailure({required this.failure});

  final AppFailure failure;

  @override
  ConsumerState<_BootFailure> createState() => _BootFailureState();
}

class _BootFailureState extends ConsumerState<_BootFailure> {
  @override
  void initState() {
    super.initState();
    ErrorReporter.report(widget.failure, context: 'boot');
  }

  @override
  Widget build(BuildContext context) => FailureView(
    failure: widget.failure,
    onRetry: () => ref.invalidate(bootLocationProvider),
  );
}
