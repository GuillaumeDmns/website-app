import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Châtelet, used before the map or the position is known
const parisCenter = LatLng(48.8584, 2.3470);

/// User position, null when unavailable (permission denied, no location service, desktop without GeoClue…).
final userLocationProvider = StreamProvider<LatLng?>((ref) async* {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield null;
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }

    if (!kIsWeb) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        yield LatLng(last.latitude, last.longitude);
      }
    }

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
    ).map<LatLng?>((position) => LatLng(position.latitude, position.longitude));
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
