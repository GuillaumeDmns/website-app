import 'dart:math' as math;

import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/utils/geo.dart';

/// The user's position as shown in GO between two fixes (a fix comes every second at best, often less): it glides to
/// each new fix instead of jumping there, then goes on along the way at the measured speed until the next one, a few
/// meters at most. The fixes themselves still drive the tracker: this is only what the map shows.
class GoSmoother {
  /// Time to glide from where the user was shown to a new fix
  static const glide = Duration(milliseconds: 900);

  /// Farthest the user is shown ahead of the last fix, in meters
  static const maxAhead = 12.0;

  /// Speeds below are standing still (GPS noise), above not on foot or by bike (m/s)
  static const minSpeed = 0.4;
  static const maxSpeed = 9.0;

  /// Fixes less accurate than this give no speed to go on with (m)
  static const maxAccuracy = 30.0;

  /// Farther from the way than this, the user doesn't follow it: no going on along it (m)
  static const nearPath = 25.0;

  LatLng? _from;
  LatLng? _fix;
  DateTime? _fixAt;
  double _speed = 0;
  MeasuredPolyline? _path;
  double _along = 0;
  LatLng? _shown;

  /// Forgets the fixes (a new GO session)
  void reset() {
    _from = null;
    _fix = null;
    _fixAt = null;
    _path = null;
    _shown = null;
    _speed = 0;
    _along = 0;
  }

  /// A new fix received at [at]; [path]: the way being walked or ridden by bike, if any
  void fix(LatLng position, DateTime at, {double? speed, double? accuracy, MeasuredPolyline? path}) {
    // The first one is shown at once
    _from = _shown ?? position;
    _fix = position;
    _fixAt = at;
    final usable = speed != null && speed >= minSpeed && speed <= maxSpeed && (accuracy == null || accuracy <= maxAccuracy);
    _speed = usable ? speed : 0;
    final projection = path?.project(position);
    _path = projection != null && projection.distance <= nearPath ? path : null;
    _along = projection?.along ?? 0;
  }

  /// Where to show the user at [now], null before the first fix
  LatLng? at(DateTime now) {
    final fix = _fix;
    final from = _from;
    final fixAt = _fixAt;
    if (fix == null || from == null || fixAt == null) {
      return null;
    }
    final elapsed = now.difference(fixAt);
    // Going on along the way: the way's own move from where the fix is on it, applied to the fix (a fix beside the way
    // stays beside it)
    var target = fix;
    final path = _path;
    final ahead = _ahead(elapsed);
    if (path != null && ahead > 0) {
      final start = path.pointAt(_along);
      final end = path.pointAt(_along + ahead);
      target = LatLng(fix.latitude + end.latitude - start.latitude, fix.longitude + end.longitude - start.longitude);
    }
    final t = (elapsed.inMilliseconds / glide.inMilliseconds).clamp(0.0, 1.0);
    final eased = 1 - (1 - t) * (1 - t);
    return _shown = LatLng(
      from.latitude + (target.latitude - from.latitude) * eased,
      from.longitude + (target.longitude - from.longitude) * eased,
    );
  }

  /// The position shown still changes after [now]: worth drawing again
  bool moving(DateTime now) {
    final fixAt = _fixAt;
    if (fixAt == null) {
      return false;
    }
    final elapsed = now.difference(fixAt);
    return elapsed < glide || (_path != null && _speed > 0 && _ahead(elapsed) < maxAhead);
  }

  double _ahead(Duration elapsed) =>
      _path == null || elapsed.isNegative ? 0 : math.min(_speed * elapsed.inMilliseconds / 1000, maxAhead);
}
