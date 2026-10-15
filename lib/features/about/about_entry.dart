import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';

/// Opens About from a header (Arc History). Opening it changes nothing and
/// contacts nothing.
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'About NextRep',
    icon: const Icon(Icons.info_outline_rounded),
    onPressed: () => context.push(AppRoutes.about),
  );
}

/// Opens About from a page without a header (onboarding, setup, a
/// completed Arc).
class AboutLink extends StatelessWidget {
  const AboutLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => context.push(AppRoutes.about),
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    icon: const Icon(Icons.info_outline_rounded),
    label: const Text('About NextRep'),
  );
}
