import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../domain/winter_arc/winter_arc_session.dart';
import '../features/celebration/celebration_overlay.dart';
import '../shared/widgets/failure_view.dart';
import '../shared/widgets/winter_background.dart';
import 'arc_status.dart';
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
/// as the initial location; later navigation is driven by the features and
/// by the arc's lifecycle status (a close-out redirects to the summary).
class _RoutedApp extends ConsumerStatefulWidget {
  const _RoutedApp({required this.initialLocation});

  final String initialLocation;

  @override
  ConsumerState<_RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends ConsumerState<_RoutedApp> {
  late final _status = ValueNotifier<WinterArcStatus?>(
    ref.read(arcStatusProvider),
  );
  late final GoRouter _router = buildAppRouter(
    initialLocation: widget.initialLocation,
    status: _status,
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual(arcStatusProvider, (_, next) => _status.value = next);
  }

  @override
  void dispose() {
    _router.dispose();
    _status.dispose();
    super.dispose();
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
