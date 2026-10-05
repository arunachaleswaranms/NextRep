import 'package:flutter/material.dart';

/// A screen (or section) that is still reading from storage. Labelled, so
/// a screen reader announces it instead of an unnamed progress bar.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading'));
}
