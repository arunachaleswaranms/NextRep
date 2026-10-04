import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../domain/winter_arc/current_arc_service.dart';
import '../features/celebration/celebration_overlay.dart';
import '../shared/widgets/failure_view.dart';
import '../shared/widgets/winter_background.dart';
import 'arc_status.dart';
import 'dependencies.dart';
import 'router/app_router.dart';
import 'theme/winter_theme.dart';

class NextRepApp extends ConsumerWidget {
  const NextRepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootLocationProvider);
    return switch (boot) {
      AsyncData(:final value) => _RoutedApp(initialLocation: value),
      AsyncError(:final error, :final stackTrace) => _StatusApp(
        child: _BootFailure(failure: toAppFailure(error, stackTrace)),
      ),
      _ => const _StatusApp(child: Center(child: CircularProgressIndicator())),
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
/// new one).
class _RoutedApp extends ConsumerStatefulWidget {
  const _RoutedApp({required this.initialLocation});

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
  StreamSubscription<String?>? _taps;

  @override
  void initState() {
    super.initState();
    ref.listenManual(arcResolutionProvider, (previous, next) {
      _resolution.value = next;
      if (previous?.active?.id != next?.active?.id) _syncReminders();
    });
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _taps = ref.read(reminderTapsProvider).listen(_openReminder);
    _syncReminders();
  }

  @override
  void dispose() {
    unawaited(_taps?.cancel());
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
