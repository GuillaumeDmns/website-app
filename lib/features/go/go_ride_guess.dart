import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../journey/journey_retime.dart';
import 'go_tracker.dart';

/// On board, which of the departures seen at the stop the user is on, guessed without ever asking them: at first the
/// one that left when they did, then, at each station on the way where those departures differ, the ones that stop
/// there or run through it as the vehicle does (a direct train runs through the stations a stopping one serves).
/// Checked again at every such station until the alighting stop: a wrong guess (two trains leaving 30 s apart, a
/// stop at a signal) is put right on its own.
class RideGuess {
  RideGuess._(this.step, this._ride, this.candidates, this._scores, this._stations, this._current);

  /// [rides]: the departures seen for the ride [step] (index in the tracker's steps, [ride]), the user having left
  /// at [departed]. The candidates are those whose stops are known that left about then.
  factory RideGuess.start(int step, GoStep ride, List<Ride> rides, {required DateTime departed}) {
    final candidates = <Ride>[];
    for (final candidate in rides) {
      if (candidate.stops.length >= 2 && !candidate.departure.cancelled &&
          candidate.departure.time.difference(departed).abs() <= window &&
          !candidates.any((other) => sameDeparture(other, candidate))) {
        candidates.add(candidate);
      }
    }
    // The departure time seen: the further from it a candidate left, the less likely it is the one (30 s off is
    // little, two minutes much; a station may still say otherwise)
    final scores = [
      for (final candidate in candidates) -math.min(_maxTimingPenalty, _timingPenalty(candidate.departure.time.difference(departed))),
    ];
    return RideGuess._(step, ride, candidates, scores, _stationsApart(ride, candidates), _followed(ride.section, candidates));
  }

  static double _timingPenalty(Duration gap) {
    final x = gap.inMilliseconds / _timing.inMilliseconds;
    return x * x / 2;
  }

  /// Departures leaving this close to the user are the ones they may be on
  static const window = Duration(minutes: 3);

  /// How far a departure time may be from the one seen (GPS, real time) for the same vehicle
  static const _timing = Duration(seconds: 30);
  static const _maxTimingPenalty = 4.0;

  /// A vehicle at a station is at most this far before or after it along the way (where the user is in a 200 m train,
  /// where the stop's position is on its platform)
  static const _zone = 200.0;

  /// Stopped: slower than this (m/s) by the GPS and along the way, for this long
  static const _stillSpeed = 1.0;
  static const _stillRate = 1.5;
  static const _stillFor = Duration(seconds: 15);

  /// Running through: never slower than this (m/s), fixes never further apart than [_maxGap] (a stop can't hide
  /// between them)
  static const _throughSpeed = 5.0;
  static const _maxGap = Duration(seconds: 15);

  /// What a station tells: a vehicle that ran through it doesn't stop there, almost surely; one that stopped may
  /// still not serve it (a signal)
  static const _ranThroughPenalty = 8.0;
  static const _stoppedPenalty = 3.0;

  /// Another candidate is followed once this much more likely than the one followed
  static const _margin = 2.0;

  /// Fixes less accurate (m), or further from the way, tell nothing about a station
  static const _maxAccuracy = 50.0;
  static const _nearWay = 100.0;

  final int step;
  final GoStep _ride;
  final List<Ride> candidates;
  final List<double> _scores;
  final List<_Station> _stations;

  /// Index of the candidate the journey follows, -1 when none (the planned stops are not one of theirs)
  int _current;

  double _along = 0;
  ({DateTime at, double along})? _last;

  /// The candidate the journey should follow now, when it is not the one followed
  Ride? get better {
    if (candidates.isEmpty) {
      return null;
    }
    var best = _current < 0 ? 0 : _current;
    for (var i = 0; i < candidates.length; i++) {
      if (_scores[i] > _scores[best]) {
        best = i;
      }
    }
    if (best == _current) {
      return null;
    }
    // Following none of them (stops not known): only one about as likely as can be, left within a minute
    final likely = _current < 0 ? _scores[best] >= -_margin : _scores[best] - _scores[_current] >= _margin;
    return likely ? candidates[best] : null;
  }

  /// The journey now follows [ride] (one of [candidates])
  void follow(Ride ride) => _current = candidates.indexWhere((candidate) => sameDeparture(candidate, ride));

  /// A fix on board at [at]: [speed] in m/s when known, [accuracy] in meters
  void observe(DateTime at, LatLng position, {double? speed, double? accuracy}) {
    if ((accuracy ?? 0) > _maxAccuracy) {
      return;
    }
    final projection = _ride.line.project(position, minAlong: math.max(0, _along - 50));
    if (projection == null || projection.distance > _nearWay) {
      return;
    }
    _along = math.max(_along, projection.along);
    final previous = _last;
    _last = (at: at, along: _along);
    if (previous == null || !at.isAfter(previous.at)) {
      return;
    }
    final gap = at.difference(previous.at);
    final rate = (_along - previous.along) / (gap.inMilliseconds / 1000);
    final still = (speed == null || speed < _stillSpeed) && rate < _stillRate;
    final through = (speed ?? rate) >= _throughSpeed && rate >= _stillRate;

    for (final station in _stations) {
      if (station.decided) {
        continue;
      }
      final start = station.along - _zone;
      if (_along < start) {
        // On the way to it: the crossing is timed from the last fix before it
        station.approached = true;
        station.maxGap = Duration.zero;
        continue;
      }
      if (gap > station.maxGap) {
        station.maxGap = gap;
      }
      if (_along <= station.along + _zone) {
        if (still && previous.along >= start) {
          station.still += gap;
        }
        if (!through) {
          station.slow = true;
        }
        if (station.still >= _stillFor) {
          _decide(station, stopped: true);
        }
        continue;
      }
      // Beyond it
      if (station.still >= _stillFor) {
        _decide(station, stopped: true);
      } else if (station.approached && !station.slow && station.maxGap <= _maxGap) {
        _decide(station, stopped: false);
      } else {
        // Not seen well enough
        station.decided = true;
      }
    }
  }

  void _decide(_Station station, {required bool stopped}) {
    station.decided = true;
    for (var i = 0; i < candidates.length; i++) {
      final serves = station.stopping.contains(i);
      if (stopped && !serves) {
        _scores[i] -= _stoppedPenalty;
      } else if (!stopped && serves) {
        _scores[i] -= _ranThroughPenalty;
      }
    }
  }

  /// The stations between the boarding and alighting stops where the candidates differ, along the way
  static List<_Station> _stationsApart(GoStep ride, List<Ride> candidates) {
    final byName = <String, _Station>{};
    for (final (index, candidate) in candidates.indexed) {
      var minAlong = 0.0;
      for (final stop in candidate.stops.sublist(1, candidate.stops.length - 1)) {
        final along = ride.line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong)?.along ?? minAlong;
        minAlong = along;
        byName.putIfAbsent(stop.name, () => _Station(along)).stopping.add(index);
      }
    }
    return byName.values.where((station) => station.stopping.length < candidates.length).toList()
      ..sort((a, b) => a.along.compareTo(b.along));
  }

  /// The candidate whose stops are the ride's (same stations, a few hundred meters apart at most), leaving closest to
  /// it
  static int _followed(JourneySection section, List<Ride> candidates) {
    var followed = -1;
    Duration? closest;
    for (final (index, candidate) in candidates.indexed) {
      final stops = candidate.stops;
      if (stops.length != section.stops.length) {
        continue;
      }
      var same = true;
      for (var k = 0; k < stops.length && same; k++) {
        same = metersBetween(LatLng(stops[k].lat, stops[k].lon), LatLng(section.stops[k].lat, section.stops[k].lon)) < 300;
      }
      final gap = candidate.departure.time.difference(section.departure).abs();
      if (same && (closest == null || gap < closest)) {
        followed = index;
        closest = gap;
      }
    }
    return followed;
  }
}

/// The same departure in two lists received at different times, like [sameRide], but two trains leaving 30 s apart
/// (a direct one and a stopping one) stay two: same train number, else same scheduled time
bool sameDeparture(Ride a, Ride b) {
  final x = a.departure;
  final y = b.departure;
  if (x.trainNumber != null && y.trainNumber != null) {
    return x.trainNumber == y.trainNumber;
  }
  if (x.aimedTime != null && y.aimedTime != null) {
    return x.aimedTime == y.aimedTime;
  }
  return sameRide(a, b);
}

/// A station where the candidates differ, and what the fixes showed there
class _Station {
  _Station(this.along);

  /// Meters along the ride's way
  final double along;

  /// The candidates that stop there
  final stopping = <int>{};

  bool approached = false;
  bool slow = false;
  Duration still = Duration.zero;

  /// Longest time between two fixes since the last one before the station
  Duration maxGap = Duration.zero;
  bool decided = false;
}
