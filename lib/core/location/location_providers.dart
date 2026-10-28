import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'position_feed.dart';

/// Châtelet, used before the map or the position is known
const parisCenter = LatLng(48.8584, 2.3470);

/// Why the position is unavailable, when it can be fixed by the user
enum LocationIssue {
  /// Location turned off on the device
  serviceDisabled,

  /// Permission refused
  permissionDenied,
}

class LocationIssueController extends Notifier<LocationIssue?> {
  @override
  LocationIssue? build() => null;

  void set(LocationIssue? issue) => state = issue;
}

final locationIssueProvider = NotifierProvider<LocationIssueController, LocationIssue?>(LocationIssueController.new);

/// Opens the system settings that fix [issue] (mobile only), then retries
Future<void> fixLocationIssue(WidgetRef ref, LocationIssue issue) async {
  switch (issue) {
    case LocationIssue.serviceDisabled:
      await Geolocator.openLocationSettings();
    case LocationIssue.permissionDenied:
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
  }
  ref.invalidate(userLocationProvider);
}

/// User position, null when unavailable (permission denied, no location service, desktop without GeoClue…).
final userLocationProvider = StreamProvider<LatLng?>((ref) async* {
  void report(LocationIssue? issue) => Future.microtask(() => ref.read(locationIssueProvider.notifier).set(issue));
  final feed = ref.watch(positionFeedProvider);

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      report(LocationIssue.serviceDisabled);
      yield null;
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      report(LocationIssue.permissionDenied);
      yield null;
      return;
    }
    report(null);

    LatLng? shown;
    if (!kIsWeb) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        yield shown = LatLng(last.latitude, last.longitude);
      }
    }

    // The app's single feed (GO may ask it a fix a second): a new position every 25 m here, as without GO
    yield* feed.fixes.map((fix) => LatLng(fix.latitude, fix.longitude)).where((position) {
      final moved = shown == null || metersBetween(shown!, position) >= regularDistanceFilter;
      if (moved) {
        shown = position;
      }
      return moved;
    });
  } catch (e) {
    debugPrint('Location unavailable: $e');
    yield null;
  }
});

/// Center of the map once the user stopped moving it
class MapCenterController extends Notifier<LatLng> {
  @override
  LatLng build() => parisCenter;

  void update(LatLng center) => state = center;
}

final mapCenterProvider = NotifierProvider<MapCenterController, LatLng>(MapCenterController.new);

/// Where "nearby" means: the user when located, the map center otherwise.
final nearbyOriginProvider = Provider<({LatLng position, bool isUser})>((ref) {
  final user = ref.watch(userLocationProvider).value;
  return user != null ? (position: user, isUser: true) : (position: ref.watch(mapCenterProvider), isUser: false);
});

/// Current time, ticking every 15 s, for "3 min" labels
final nowProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 15), (_) => DateTime.now());
});
