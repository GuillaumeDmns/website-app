import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../platform/app_shown.dart';

/// Meters moved before the regular position (the map's dot, nearby departures) changes
const regularDistanceFilter = 25;

/// How often GO needs a position fix, whatever the distance moved (a user waiting at a stop must not look like one
/// without GPS)
@immutable
class LocationNeed {
  const LocationNeed(this.interval);

  final Duration interval;

  @override
  bool operator ==(Object other) => other is LocationNeed && other.interval == interval;

  @override
  int get hashCode => interval.hashCode;

  @override
  String toString() => 'LocationNeed(${interval.inMilliseconds} ms)';
}

/// The device's position fixes, for the whole app. Geolocator keeps a single stream of positions on Android (a second
/// request gets the first one's stream, its settings included), so the app has this one feed: the regular settings
/// (the map's dot and the nearby departures: a fix every 25 m), opened again with GO's [need] while a journey is
/// followed, and back after. Closed while nobody listens, and while the app is not on screen unless GO needs it (its
/// foreground service keeps the journey followed with the screen off).
class PositionFeed {
  PositionFeed({Stream<Position> Function(LocationSettings settings)? open}) : _open = open ?? _geolocator;

  static Stream<Position> _geolocator(LocationSettings settings) => Geolocator.getPositionStream(locationSettings: settings);

  final Stream<Position> Function(LocationSettings settings) _open;
  late final _fixes = StreamController<Position>.broadcast(onListen: _update, onCancel: _update);
  StreamSubscription<Position>? _subscription;

  /// What the device's stream was last opened for: null while closed
  ({LocationNeed? need})? _opened;
  LocationNeed? _need;
  bool _shown = true;
  bool _disposed = false;

  /// Changes waiting for the previous stream to be closed (Geolocator only forgets it then)
  Future<void> _switching = Future.value();

  /// The fixes as they come; errors (location turned off…) are passed on
  Stream<Position> get fixes => _fixes.stream;

  /// What GO needs now, null when no journey is followed
  LocationNeed? get need => _need;

  set need(LocationNeed? need) {
    if (need != _need) {
      _need = need;
      _update();
    }
  }

  /// The app is on screen
  set shown(bool shown) {
    if (shown != _shown) {
      _shown = shown;
      _update();
    }
  }

  /// Whether the device's stream is open, and for what (for the tests)
  ({LocationNeed? need})? get opened => _opened;

  void _update() {
    final wanted = !_disposed && _fixes.hasListener && (_shown || _need != null) ? (need: _need) : null;
    if (wanted == _opened) {
      return;
    }
    _opened = wanted;
    final previous = _subscription;
    _subscription = null;
    _switching = _switching.then((_) async {
      try {
        await previous?.cancel();
      } catch (_) {
        // Closed anyway
      }
      // Changed again meanwhile: the latest change opens it
      if (_disposed || wanted == null || wanted != _opened || _subscription != null) {
        return;
      }
      try {
        _subscription = _open(settingsFor(wanted.need)).listen(_fixes.add, onError: _fixes.addError);
      } catch (e) {
        _fixes.addError(e);
      }
    });
  }

  /// The device's settings: the app's regular ones, or GO's (every fix, at [LocationNeed.interval] where the platform
  /// allows choosing it)
  static LocationSettings settingsFor(LocationNeed? need) {
    if (need == null) {
      return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: regularDistanceFilter);
    }
    if (kIsWeb) {
      return WebSettings(accuracy: LocationAccuracy.best, distanceFilter: 0, maximumAge: Duration.zero);
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(accuracy: LocationAccuracy.best, distanceFilter: 0, intervalDuration: need.interval),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
        ),
      _ => const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    };
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _fixes.close();
  }
}

final positionFeedProvider = Provider<PositionFeed>((ref) {
  final feed = PositionFeed();
  ref.listen(appShownProvider, (_, shown) => feed.shown = shown, fireImmediately: true);
  ref.onDispose(feed.dispose);
  return feed;
});
