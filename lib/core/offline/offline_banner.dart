import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/location_providers.dart';
import '../utils/time_format.dart';
import 'offline_cache.dart';

/// "Hors ligne" pill over the map while the server can't be reached, with the age of the data shown
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(offlineProvider);
    if (since == null) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final at = since.toLocal();
    final when = DateTime(at.year, at.month, at.day) == today ? formatClock(at) : '${formatDay(at, today)} ${formatClock(at)}';
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 18, color: scheme.onInverseSurface),
              const SizedBox(width: 8),
              Text('Hors ligne · données du $when', style: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
