import 'package:flutter/material.dart';

/// Shown when [ExploreApp]'s boot sequence throws.
///
/// Kept out of `main.dart`'s `build` so the failure branch is reachable from a
/// widget test — boot neither completes nor fails under `flutter_test`, so
/// driving this screen through `_boot` is not possible.
class BootErrorScreen extends StatelessWidget {
  const BootErrorScreen({super.key, required this.onRetry});

  /// Invoked by the "Try again" button.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text(
                  "Couldn't load the chart explorer",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'This is usually a temporary network issue. Please '
                  'check your connection and try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
