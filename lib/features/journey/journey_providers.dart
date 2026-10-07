import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../l10n/l10n.dart';
import 'journey_request.dart';
import 'journey_retime.dart';

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
      throw ApiException(currentL10n.locationUnavailableChooseStart);
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
        bikeShare: request.bikeShare,
      );
});

/// Next departures of a ride's line from its boarding stop that stop at its alighting stop, with their arrival there,
/// from the time the traveller gets there (now when null), refreshed every 30 s while shown
final rideOptionsProvider = FutureProvider.autoDispose.family<List<Ride>, RideKey>((ref, key) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(mobilityApiProvider).lineRides(key.lineId, from: key.from, to: key.to, after: key.after, limit: 8);
});

/// Departures of a ride for [retimeJourney], from a widget: watched, so that the journey follows real time. Lists
/// are only asked within the next 12 hours (the API's limit).
RideLookup watchRides(WidgetRef ref, DateTime now) => (key) {
      final after = key.after;
      if (after != null && after.isAfter(now.add(const Duration(hours: 11)))) {
        return null;
      }
      return ref.watch(rideOptionsProvider(key)).value;
    };

/// A journey option found again from a detail link (`Routes.journeyDetailOf`): the search run at the option's
/// departure time, then the option with the same lines leaving closest to it. Null when none is found.
final sharedJourneyProvider = FutureProvider.autoDispose.family<JourneyOption?, String>((ref, query) async {
  final params = Uri.splitQueryString(query);
  final departure = DateTime.tryParse(params['dep'] ?? '');
  final request = JourneyRequest.fromQuery(params);
  if (departure == null || !request.isComplete) {
    return null;
  }
  final plan = await ref.watch(journeyPlanProvider(request.copyWith(datetime: () => departure, arriveBy: false)).future);
  final lines = params['lines'] ?? '';
  JourneyOption? best;
  for (final option in plan.journeys) {
    final sameLines = option.rides.map((ride) => ride.line?.id ?? '').join(',') == lines;
    final bestSameLines = best != null && best.rides.map((ride) => ride.line?.id ?? '').join(',') == lines;
    final closer = best == null ||
        option.departure.difference(departure).abs() < best.departure.difference(departure).abs();
    if (best == null || (sameLines && !bestSameLines) || (sameLines == bestSameLines && closer)) {
      best = option;
    }
  }
  return best;
});

/// Option opened in the detail page (kept here rather than in the URL: it is a snapshot of a search)
class SelectedJourney extends Notifier<JourneyOption?> {
  @override
  JourneyOption? build() => null;

  /// Search the option comes from (its options are reused to recalculate in GO mode)
  JourneyRequest? request;

  void select(JourneyOption journey, JourneyRequest request) {
    this.request = request;
    state = journey;
  }
}

final selectedJourneyProvider = NotifierProvider<SelectedJourney, JourneyOption?>(SelectedJourney.new);
