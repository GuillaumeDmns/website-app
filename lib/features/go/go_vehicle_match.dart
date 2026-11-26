import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../journey/journey_retime.dart';
import 'go_tracker.dart';

/// Which of the departures seen at the stop the user is on, worked out without ever asking them, from the moment they
/// wait for it to the alighting stop: always the most likely one, the one the journey aimed at only a little ahead of
/// the others ([_aimedBonus]). Each departure is a candidate with a score; what the GPS shows takes points off the ones
/// it doesn't fit, once per thing seen (not per fix: fixes a second apart say the same thing). Strong signs don't
/// depend on how the vehicle runs:
/// - still on the platform (or seated in the train waiting there) after a departure left: not on that one
///   ([stillAtPlatform]), unless the real time said it was still at the stop since;
/// - seen away from the stop at a time: a departure leaving after that had not left ([departed]);
/// - at a station where their stops differ, a vehicle running through it (never under 5 m/s, fixes at most 15 s apart)
///   doesn't stop there: a direct train runs through the stations a stopping one serves;
/// - a departure the real time says is still at the stop while the user is already down the line ([seen]).
/// Weak ones do (a slowdown, a stop at a signal, a rough GPS):
/// - how far a departure left from when the user did ([departed]);
/// - on board, where each departure should be by its real time and its stop times, against where a precise fix puts the
///   user ([observe], once a minute): the user ahead of where one should be is a sign against it, behind it only takes
///   points off (a slowing train is behind its times, never ahead of them);
/// - a vehicle standing at a station 15 s that only other candidates serve (a signal, maybe).
/// Another candidate is followed once 2 points more likely and by a strong sign, or two weak ones more than the one
/// followed ([better]): a rough GPS gives few signs and leaves the departure aimed at; a slowing train never makes it
/// another one. Once one leads every other by a strong sign's worth, each of them with a strong sign against it, it is
/// the one until the alighting stop ([_locked]).
class VehicleMatch {
  /// [followed]: the real-time departure the journey aims at for that ride, when known (found among the candidates by
  /// what it is: [sameVehicleDeparture])
  VehicleMatch(this.step, this._ride, {Departure? followed}) : _followedDeparture = followed;

  /// [rides]: the departures seen for the ride [step] (index in the tracker's steps, [ride]), the user seen leaving at
  /// [departed] ([measured]: false when it was only assumed; [seenAway]: when a fix saw them away from the stop)
  factory VehicleMatch.start(int step, GoStep ride, List<Ride> rides,
          {required DateTime departed, bool measured = true, DateTime? seenAway, Departure? followed}) =>
      VehicleMatch(step, ride, followed: followed)
        ..seen(rides, departed)
        ..departed(departed, measured: measured, seenAway: seenAway);

  /// Departures leaving this close to the user are the ones they may be on
  static const window = Duration(minutes: 3);

  /// How far a departure time may be from the one seen (GPS, real time) for the same vehicle
  static const _timing = Duration(seconds: 30);
  static const _maxTimingPenalty = 4.0;

  /// What a strong sign says against a candidate: it surely is not that one
  static const _ruledOut = 8.0;

  /// The departure the journey aimed at, a little more likely than the others before anything is seen: two trains
  /// leaving 30 s apart with the same stops are told apart by nothing else
  static const _aimedBonus = 1.0;

  /// A weak sign counts from this many points (a departure a few seconds off is no sign)
  static const _weakSign = 1.0;

  /// A departure this far past is gone, whatever its time said (the real time is a little off)
  static const _leftSince = Duration(seconds: 60);

  /// One leaving this long after the user was seen away from the stop had not left
  static const _notYet = Duration(seconds: 60);

  /// The user seen leaving: a departure this far off that time is another one
  static const _measuredOff = Duration(seconds: 90);

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

  /// Another candidate is followed once this much more likely than the one followed (and by enough signs: [better])
  static const _margin = 2.0;

  /// Fixes less accurate (m), or further from the way, tell nothing about a station
  static const _maxAccuracy = 50.0;
  static const _nearWay = 100.0;

  /// A fix this precise is the GPS's: where the user is, for [_positionPenalty]
  static const _preciseAccuracy = 30.0;

  final int step;
  GoStep _ride;
  Departure? _followedDeparture;

  /// Every departure seen, whether it may be the one or not
  final _all = <_Candidate>[];

  /// The ones that left about when the user did, once they did ([departed]); empty before
  List<_Candidate> _candidates = const [];
  List<_Station> _stations = const [];

  /// Index in [_candidates] of the one the journey follows, -1 when none (the departure aimed at is none of them)
  int _current = -1;

  /// Index in [_candidates] of the one surely taken, once it is ([_lock])
  int? _locked;

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
    final locked = _locked ?? _lock();
    if (locked != null) {
      return locked == _current ? null : _candidates[locked].ride;
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
    final candidate = _candidates[best];
    // Following none of them (the departure aimed at left at another time): only one about as likely as can be
    if (_current < 0) {
      return candidate.score >= -_margin ? candidate.ride : null;
    }
    // More likely by enough, and by a strong sign or two weak ones: never by a slowdown or a rough fix alone
    final followed = _candidates[_current];
    final signs = followed.strong > candidate.strong || followed.weak >= candidate.weak + 2;
    return candidate.score - followed.score >= _margin && signs ? candidate.ride : null;
  }

  /// The candidate surely taken: ahead of every other one by a strong sign's worth, each of them with a strong sign
  /// against it; from then on nothing seen changes it (a train slowing down, a stop at a signal)
  int? _lock() {
    if (_candidates.length < 2) {
      return null;
    }
    var leader = 0;
    for (var i = 1; i < _candidates.length; i++) {
      if (_candidates[i].score > _candidates[leader].score) {
        leader = i;
      }
    }
    for (var i = 0; i < _candidates.length; i++) {
      if (i != leader && (_candidates[leader].score - _candidates[i].score < _ruledOut || _candidates[i].strong == 0)) {
        return null;
      }
    }
    return _locked = leader;
  }

  /// Every departure seen at the stop, departed ones included
  List<Ride> get seenRides => [for (final candidate in _all) candidate.ride];

  /// The journey now follows [ride] (one of [candidates]; before the user left, the departure aimed at: one chosen
  /// in a card while waiting is the one given the aimed bonus, not the one aimed at when the waiting began)
  void follow(Ride ride) {
    _followedDeparture = ride.departure;
    _current = _candidates.indexWhere((candidate) => sameDeparture(candidate.ride, ride));
  }

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
          candidate.against(_ruledOut, strong: true);
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
        candidate.against(_ruledOut, strong: true);
      }
    }
  }

  /// The user left the stop at [at] ([measured]: seen leaving, by fixes moving fast near the stop; else assumed then,
  /// underground or seen on board only further), seen away from it at [seenAway] when a fix did: the candidates are
  /// the departures whose stops are known that left from about then to about that time
  void departed(DateTime at, {bool measured = false, DateTime? seenAway}) {
    if (_departedAt != null) {
      return;
    }
    _departedAt = at;
    final until = seenAway != null && seenAway.isAfter(at) ? seenAway : at;
    final candidates = <_Candidate>[];
    for (final candidate in _all) {
      final departure = candidate.ride.departure;
      final time = departure.time;
      if (candidate.ride.stops.length < 2 || departure.cancelled || time.isBefore(at.subtract(window)) ||
          time.isAfter(until.add(window)) || candidates.any((other) => sameDeparture(other.ride, candidate.ride))) {
        continue;
      }
      // When the user left: the further from it a candidate left, the less likely it is the one (30 s off is little,
      // two minutes much; a station may still say otherwise)
      final gap = time.isBefore(at) ? time.difference(at) : time.isAfter(until) ? time.difference(until) : Duration.zero;
      // Seen leaving at a time, one leaving a minute and a half off it is another one; seen away from the stop before
      // it left, not that one either. An assumed time says no more than how likely.
      if (measured && gap.abs() > _measuredOff || seenAway != null && time.isAfter(seenAway.add(_notYet))) {
        candidate.against(_ruledOut, strong: true);
      } else {
        candidate.against(math.min(_maxTimingPenalty, _timingPenalty(gap)));
      }
      candidates.add(candidate);
    }
    _candidates = candidates;
    _stations = _stationsApart(_ride, candidates);
    _current = _aimedIndex(candidates);
    if (_current >= 0) {
      candidates[_current].score += _aimedBonus;
    }
    for (final candidate in candidates) {
      candidate.alongs = _alongs(_ride, candidate.ride);
    }
  }

  /// Index in [candidates] of the departure the journey aims at: the one given, found by what it is; without one, the
  /// one leaving closest to when the ride does, within a minute; -1 when none
  int _aimedIndex(List<_Candidate> candidates) {
    final aimed = _followedDeparture;
    if (aimed != null) {
      return candidates.indexWhere((candidate) => sameVehicleDeparture(candidate.ride.departure, aimed));
    }
    final planned = _ride.section.departure;
    var best = -1;
    var bestGap = const Duration(seconds: 60);
    for (final (index, candidate) in candidates.indexed) {
      final departure = candidate.ride.departure;
      final real = departure.time.difference(planned).abs();
      final scheduled = departure.aimedTime?.difference(planned).abs() ?? real;
      final gap = real < scheduled ? real : scheduled;
      if (gap < bestGap) {
        best = index;
        bestGap = gap;
      }
    }
    return best;
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
      // Behind where it should be: a slowdown of the very vehicle followed may say as much, its score only; ahead of
      // it, no slowdown explains that: a sign
      candidate.against(math.min(_maxPositionPenalty, x * x / 2), sign: along > expected);
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
        _candidates[i].against(_stoppedPenalty);
      } else if (!stopped && serves) {
        _candidates[i].against(_ranThroughPenalty, strong: true);
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
}

/// The same departure in two lists received at different times, like [sameRide], but two trains leaving 30 s apart
/// (a direct one and a stopping one) stay two: same train number, else same scheduled time
bool sameDeparture(Ride a, Ride b) => sameVehicleDeparture(a.departure, b.departure);

/// The same departure of a vehicle, whatever the real time made of its time since: its train number when both have one
/// (SNCF), else its scheduled time (and its mission when both have one: two trains of the same minute), else its time
/// within a minute
bool sameVehicleDeparture(Departure x, Departure y) {
  if (x.trainNumber != null && y.trainNumber != null) {
    return x.trainNumber == y.trainNumber;
  }
  if (x.mission != null && y.mission != null && x.mission != y.mission) {
    return false;
  }
  if (x.aimedTime != null && y.aimedTime != null) {
    return x.aimedTime == y.aimedTime;
  }
  return (x.aimedTime ?? x.time).difference(y.aimedTime ?? y.time).abs() < const Duration(seconds: 60);
}

/// A departure the user may be on, and what was seen of it
class _Candidate {
  _Candidate(this.ride);

  Ride ride;
  double score = 0;

  /// Signs seen against it: strong ones (it surely isn't that one), weak ones (it may not be)
  int strong = 0;
  int weak = 0;

  /// [points] taken off for a sign against it ([sign]: false when it may come from the vehicle running late, the score
  /// only)
  void against(double points, {bool strong = false, bool sign = true}) {
    score -= points;
    if (strong) {
      this.strong++;
    } else if (sign && points >= VehicleMatch._weakSign) {
      weak++;
    }
  }

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
