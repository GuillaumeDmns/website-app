import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../journey/journey_retime.dart';
import 'go_tracker.dart';

/// Which of the departures seen at the stop the user is on, worked out without ever asking them, from the moment they
/// wait for it to the alighting stop. Each departure is a candidate with a score; what the GPS shows takes points off
/// the ones it doesn't fit, once per thing seen (not per fix: fixes a second apart say the same thing):
/// - still on the platform (or seated in the train waiting there) after a departure left: not on that one
///   ([stillAtPlatform]), unless the real time said it was still at the stop since;
/// - seen leaving at a time: the further from it a departure left, the less likely ([departed]); one leaving minutes
///   later had not left yet;
/// - on board, where each departure should be by its real time and its stop times, against where the GPS puts the user
///   ([observe], once a minute);
/// - at each station where their stops differ, whether the vehicle stopped there (15 s still) or ran through it (never
///   under 5 m/s, fixes at most 15 s apart): a direct train runs through the stations a stopping one serves;
/// - a departure the real time says is still at the stop while the user is already down the line ([seen]).
/// Checked again at every such sign until the alighting stop: a wrong guess (two trains leaving 30 s apart, a stop at
/// a signal) is put right on its own.
class VehicleMatch {
  VehicleMatch(this.step, this._ride);

  /// [rides]: the departures seen for the ride [step] (index in the tracker's steps, [ride]), the user having left at
  /// [departed]
  factory VehicleMatch.start(int step, GoStep ride, List<Ride> rides, {required DateTime departed}) =>
      VehicleMatch(step, ride)
        ..seen(rides, departed)
        ..departed(departed);

  /// Departures leaving this close to the user are the ones they may be on
  static const window = Duration(minutes: 3);

  /// How far a departure time may be from the one seen (GPS, real time) for the same vehicle
  static const _timing = Duration(seconds: 30);
  static const _maxTimingPenalty = 4.0;

  /// What a thing seen says against a candidate: it surely is not that one
  static const _ruledOut = 8.0;

  /// A departure this far past is gone, whatever its time said (the real time is a little off)
  static const _leftSince = Duration(seconds: 60);

  /// One leaving this long after the user did had not left
  static const _notYet = Duration(minutes: 2);

  /// Where it should be against where it is, at most once a minute: off by about [_spread] (plus 10 % of the way) is
  /// nothing much, three times that much
  static const _positionEvery = Duration(minutes: 1);
  static const _spread = 500.0;
  static const _maxPositionPenalty = 4.0;

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

  /// A fix this precise is the GPS's: where the user is, for [_positionPenalty]
  static const _preciseAccuracy = 30.0;

  final int step;
  GoStep _ride;

  /// Every departure seen, whether it may be the one or not
  final _all = <_Candidate>[];

  /// The ones that left about when the user did, once they did ([departed]); empty before
  List<_Candidate> _candidates = const [];
  List<_Station> _stations = const [];

  /// Index in [_candidates] of the one the journey follows, -1 when none (the planned stops are not one of theirs)
  int _current = -1;

  DateTime? _departedAt;
  double _along = 0;
  ({DateTime at, double along})? _last;
  DateTime? _positionAt;

  /// The departures the user may be on, once seen leaving
  List<Ride> get candidates => [for (final candidate in _candidates) candidate.ride];

  /// Seen leaving
  bool get hasDeparted => _departedAt != null;

  /// The journey's ride now follows another vehicle, [ride] its step (same line, its stops)
  set ride(GoStep ride) => _ride = ride;

  /// The candidate the journey should follow now, when it is not the one followed
  Ride? get better {
    if (_candidates.isEmpty) {
      return null;
    }
    var best = _current < 0 ? 0 : _current;
    for (var i = 0; i < _candidates.length; i++) {
      if (_candidates[i].score > _candidates[best].score) {
        best = i;
      }
    }
    if (best == _current) {
      return null;
    }
    // Following none of them (stops not known): only one about as likely as can be, left within a minute
    final likely = _current < 0
        ? _candidates[best].score >= -_margin
        : _candidates[best].score - _candidates[_current].score >= _margin;
    return likely ? _candidates[best].ride : null;
  }

  /// The journey now follows [ride] (one of [candidates])
  void follow(Ride ride) => _current = _candidates.indexWhere((candidate) => sameDeparture(candidate.ride, ride));

  /// The departures at the stop as received at [at] (departed ones are kept, with their last times). [userGone]: the
  /// user is down the line by then, so none the real time says is still at the stop is theirs.
  void seen(List<Ride> rides, DateTime at, {bool userGone = false}) {
    for (final ride in rides) {
      var candidate = _all.where((known) => sameDeparture(known.ride, ride)).firstOrNull;
      if (candidate == null) {
        candidate = _Candidate(ride);
        _all.add(candidate);
      } else {
        candidate.ride = ride;
      }
      if (ride.departure.atStop == true) {
        candidate.atStopAt = at;
        if (userGone && !candidate.leftBehind) {
          candidate.leftBehind = true;
          candidate.score -= _ruledOut;
        }
      }
    }
  }

  /// A precise fix at [at] puts the user still on the platform, or in the vehicle standing there: not on any departure
  /// gone by then (unless the real time said it was still there since)
  void stillAtPlatform(DateTime at) {
    for (final candidate in _all) {
      final time = candidate.ride.departure.time;
      final stillThere = candidate.atStopAt != null && !candidate.atStopAt!.isBefore(time);
      if (!candidate.gone && !stillThere && time.isBefore(at.subtract(_leftSince))) {
        candidate.gone = true;
        candidate.score -= _ruledOut;
      }
    }
  }

  /// The user left the stop at [at] (seen leaving, or assumed then underground): the candidates are the departures
  /// whose stops are known that left about then
  void departed(DateTime at) {
    if (_departedAt != null) {
      return;
    }
    _departedAt = at;
    final candidates = <_Candidate>[];
    for (final candidate in _all) {
      final departure = candidate.ride.departure;
      if (candidate.ride.stops.length >= 2 && !departure.cancelled && departure.time.difference(at).abs() <= window &&
          !candidates.any((other) => sameDeparture(other.ride, candidate.ride))) {
        final gap = departure.time.difference(at);
        // The departure time seen: the further from it a candidate left, the less likely it is the one (30 s off is
        // little, two minutes much; a station may still say otherwise)
        candidate.score -= math.min(_maxTimingPenalty, _timingPenalty(gap));
        if (gap > _notYet) {
          candidate.score -= _ruledOut;
        }
        candidates.add(candidate);
      }
    }
    _candidates = candidates;
    _stations = _stationsApart(_ride, candidates);
    _current = _followed(_ride.section, candidates);
    for (final candidate in candidates) {
      candidate.alongs = _alongs(_ride, candidate.ride);
    }
  }

  static double _timingPenalty(Duration gap) {
    final x = gap.inMilliseconds / _timing.inMilliseconds;
    return x * x / 2;
  }

  /// A fix on board at [at]: [speed] in m/s when known, [accuracy] in meters
  void observe(DateTime at, LatLng position, {double? speed, double? accuracy}) {
    if (_departedAt == null || (accuracy ?? 0) > _maxAccuracy) {
      return;
    }
    final projection = _ride.line.project(position, minAlong: math.max(0, _along - 50));
    if (projection == null || projection.distance > _nearWay) {
      return;
    }
    _along = math.max(_along, projection.along);
    if ((accuracy ?? 0) <= _preciseAccuracy) {
      _positionPenalty(at, projection.along);
    }
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

  /// Where each candidate should be at [at] by its real time against [along], where the GPS puts the user
  void _positionPenalty(DateTime at, double along) {
    final last = _positionAt;
    if (last != null && at.difference(last) < _positionEvery) {
      return;
    }
    _positionAt = at;
    final spread = _spread + along * 0.1;
    for (final candidate in _candidates) {
      final expected = _expectedAlong(candidate, at);
      if (expected == null) {
        continue;
      }
      final x = (expected - along) / spread;
      candidate.score -= math.min(_maxPositionPenalty, x * x / 2);
    }
  }

  /// Where [candidate] should be along the way at [at]: its stop times shifted by how late it left
  static double? _expectedAlong(_Candidate candidate, DateTime at) {
    final stops = candidate.ride.stops;
    final alongs = candidate.alongs;
    final first = stops.first.time;
    if (alongs == null || first == null || stops.any((stop) => stop.time == null)) {
      return null;
    }
    final departure = candidate.ride.departure;
    final delay = departure.time.difference(departure.aimedTime ?? first);
    final time = at.subtract(delay);
    if (!time.isAfter(first)) {
      return alongs.first;
    }
    for (var k = 1; k < stops.length; k++) {
      final from = stops[k - 1].time!;
      final to = stops[k].time!;
      if (time.isBefore(to)) {
        final span = to.difference(from).inMilliseconds;
        final share = span <= 0 ? 1.0 : time.difference(from).inMilliseconds / span;
        return alongs[k - 1] + (alongs[k] - alongs[k - 1]) * share;
      }
    }
    return alongs.last;
  }

  void _decide(_Station station, {required bool stopped}) {
    station.decided = true;
    for (var i = 0; i < _candidates.length; i++) {
      final serves = station.stopping.contains(i);
      if (stopped && !serves) {
        _candidates[i].score -= _stoppedPenalty;
      } else if (!stopped && serves) {
        _candidates[i].score -= _ranThroughPenalty;
      }
    }
  }

  /// Where [ride]'s stops are along [step]'s way
  static List<double> _alongs(GoStep step, Ride ride) {
    var minAlong = 0.0;
    return [
      for (final stop in ride.stops)
        minAlong = step.line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong)?.along ?? minAlong,
    ];
  }

  /// The stations between the boarding and alighting stops where the candidates differ, along the way
  static List<_Station> _stationsApart(GoStep ride, List<_Candidate> candidates) {
    final byName = <String, _Station>{};
    for (final (index, candidate) in candidates.indexed) {
      final stops = candidate.ride.stops;
      var minAlong = 0.0;
      for (final stop in stops.sublist(1, stops.length - 1)) {
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
  static int _followed(JourneySection section, List<_Candidate> candidates) {
    var followed = -1;
    Duration? closest;
    for (final (index, candidate) in candidates.indexed) {
      final stops = candidate.ride.stops;
      if (stops.length != section.stops.length) {
        continue;
      }
      var same = true;
      for (var k = 0; k < stops.length && same; k++) {
        same = metersBetween(LatLng(stops[k].lat, stops[k].lon), LatLng(section.stops[k].lat, section.stops[k].lon)) < 300;
      }
      // Its scheduled time, or its real time when the journey was moved to it
      final departure = candidate.ride.departure;
      final real = departure.time.difference(section.departure).abs();
      final aimed = departure.aimedTime?.difference(section.departure).abs() ?? real;
      final gap = aimed < real ? aimed : real;
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

/// A departure the user may be on, and what was seen of it
class _Candidate {
  _Candidate(this.ride);

  Ride ride;
  double score = 0;

  /// Last time the real time said it was at the stop
  DateTime? atStopAt;

  /// Gone while the user was still at the platform / still at the stop while the user was down the line
  bool gone = false;
  bool leftBehind = false;

  /// Its stops along the way
  List<double>? alongs;
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
