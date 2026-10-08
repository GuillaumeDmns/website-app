import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

/// Renders an [AsyncValue]: spinner while loading the first time, error with retry, then [data]. Keeps showing the
/// previous data while refreshing.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorMessage(message: error.toString(), onRetry: onRetry),
    );
  }
}

class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ],
      ),
    );
  }
}
