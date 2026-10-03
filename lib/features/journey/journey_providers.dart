import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import 'journey_request.dart';

/// Journey options for a complete request. "Ma position" is resolved to the current user position.
final journeyPlanProvider = FutureProvider.autoDispose.family<JourneyPlan, JourneyRequest>((ref, request) async {
  Future<String> resolve(JourneyPlace place) async {
    if (!place.isCurrentLocation) {
      return place.stopAreaId ?? '${place.lat},${place.lon}';
    }
    // First fix may still be coming
    final position = ref.read(userLocationProvider).value ??
        await ref.read(userLocationProvider.future).timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (position == null) {
      throw const ApiException('Position indisponible : choisissez un point de départ');
    }
    return '${position.latitude},${position.longitude}';
  }

  return ref.watch(mobilityApiProvider).journeys(
        from: await resolve(request.from!),
        to: await resolve(request.to!),
        datetime: request.datetime,
        arriveBy: request.arriveBy,
        modes: request.modes,
        wheelchair: request.wheelchair,
        walkingSpeed: request.walkingSpeed.apiName,
      );
});

/// Next departures of a line at a stop area (alternatives to the planned ride), refreshed every 30 s while shown
final rideDeparturesProvider = FutureProvider.autoDispose.family<StopDepartures, ({String stopAreaId, String lineId})>((ref, key) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(mobilityApiProvider).stopDepartures(key.stopAreaId, lineId: key.lineId, limit: 4);
});

/// Option opened in the detail page (kept here rather than in the URL: it is a snapshot of a search)
class SelectedJourney extends Notifier<JourneyOption?> {
  @override
  JourneyOption? build() => null;

  void select(JourneyOption journey) => state = journey;
}

final selectedJourneyProvider = NotifierProvider<SelectedJourney, JourneyOption?>(SelectedJourney.new);
