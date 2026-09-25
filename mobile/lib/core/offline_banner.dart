import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// A red strip across the top of every screen while the phone is offline.
/// Ventrafin has no offline mode (PRD § 5), so this says plainly that
/// nothing can be saved or loaded until the connection is back.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (!online)
          Material(
            color: scheme.error,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 18, color: scheme.onError),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "No internet connection. Entries can't be saved or loaded until you're back online.",
                        style: TextStyle(color: scheme.onError, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: !online,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Error state for data that couldn't load: the plain message and a Retry
/// button. Fills the screen, or with [compact] sits inside a card or section.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry, this.compact = false});

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            const SizedBox(width: 4),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
