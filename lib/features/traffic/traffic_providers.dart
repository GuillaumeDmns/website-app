import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';

/// Traffic state of the main lines and of every disrupted line, refreshed every 2 min while shown
final trafficProvider = FutureProvider.autoDispose<List<LineTraffic>>((ref) async {
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(mobilityApiProvider).traffic();
});

/// Worst active disruption of each disrupted line; empty while loading or on error (the traffic is a bonus there)
final lineSeveritiesProvider = Provider.autoDispose<Map<String, DisruptionSeverity>>((ref) {
  final traffic = ref.watch(trafficProvider).value ?? const <LineTraffic>[];
  return {
    for (final line in traffic)
      if (line.severity != null) line.line.id: line.severity!,
  };
});

final lineDisruptionsProvider = FutureProvider.autoDispose.family<List<Disruption>, String>(
  (ref, lineId) => ref.watch(mobilityApiProvider).lineDisruptions(lineId),
);

final stopDisruptionsProvider = FutureProvider.autoDispose.family<List<Disruption>, String>(
  (ref, stopAreaId) => ref.watch(mobilityApiProvider).stopDisruptions(stopAreaId),
);
