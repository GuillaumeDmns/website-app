import '../../core/api/models.dart';

/// Departures of a ride's line from its boarding stop to its alighting stop, from [after] on (now when null)
typedef RideKey = ({String lineId, String from, String to, DateTime? after});

/// Departures for a key, null while unknown
typedef RideLookup = List<Ride>? Function(RideKey key);

/// A ride of a retimed journey
class RidePlan {
  const RidePlan({required this.key, required this.ride, required this.earliest});

  /// Its departures, from the earliest boarding time
  final RideKey key;

  /// The departure taken, null when its departures are unknown
  final Ride? ride;

  /// When the traveller can be at the boarding stop at the earliest
  final DateTime earliest;
}

class RetimedJourney {
  const RetimedJourney(this.journey, this.rides);

  final JourneyOption journey;

  /// By section index
  final Map<int, RidePlan> rides;
}

/// Lists starting this soon start now (shared by every ride boarded soon)
const _nearFuture = Duration(minutes: 5);

/// A departure this much before the earliest boarding time is still taken (times are rounded)
const _tolerance = Duration(minutes: 1);

/// Key of the departures of [section] boarded from [earliest] on: to the minute, so that it stays the same between
/// refreshes
RideKey? rideKey(JourneySection section, DateTime earliest, DateTime now) {
  final lineId = section.line?.id;
  final from = section.from?.stopAreaId;
  final to = section.to?.stopAreaId;
  if (lineId == null || lineId.isEmpty || from == null || to == null) {
    return null;
  }
  final utc = earliest.toUtc();
  final after = earliest.isBefore(now.add(_nearFuture))
      ? null
      : DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  return (lineId: lineId, from: from, to: to, after: after);
}

/// Same departure in two lists (refreshes, or the list of another start time)
bool sameRide(Ride a, Ride b) {
  final x = a.departure;
  final y = b.departure;
  if (x.trainNumber != null && y.trainNumber != null) {
    return x.trainNumber == y.trainNumber;
  }
  return (x.aimedTime ?? x.time).difference(y.aimedTime ?? y.time).abs() < const Duration(seconds: 60);
}

/// [journey] with each ride on a real departure, like Citymapper when another departure is chosen:
/// - a ride of [choices] (by section index) takes the chosen departure;
/// - another one keeps its planned departure while it can still be caught, else takes the first departure leaving
///   after the traveller gets to its stop (arrival of the previous ride, then the walk);
/// - walks follow the ride before them, waits fill the time until the ride after, and the sections before the first
///   ride end when it leaves.
///
/// Sections before [from] are kept as they are (GO mode: the part already done). [lookup] gives the departures of
/// a ride; without them its planned times are kept, or moved after the previous ride.
RetimedJourney retimeJourney(
  JourneyOption journey, {
  required RideLookup lookup,
  required DateTime now,
  Map<int, Ride> choices = const {},
  int from = 0,
}) {
  final sections = [...journey.sections];
  final rides = <int, RidePlan>{};
  final firstRide = sections.indexWhere((section) => section.kind == SectionKind.transit, from);
  if (firstRide < 0) {
    return RetimedJourney(journey, rides);
  }

  // When the traveller can be at the first ride's stop
  DateTime cursor;
  if (from > 0) {
    cursor = _lastEnd(sections, from) ?? now;
  } else {
    final start = journey.departure.isAfter(now) ? journey.departure : now;
    cursor = start.add(Duration(seconds: _walkingBefore(sections, firstRide)));
  }

  int? waitIndex;
  for (var i = firstRide; i < sections.length; i++) {
    final section = sections[i];
    switch (section.kind) {
      case SectionKind.transit:
        final earliest = cursor;
        final key = rideKey(section, earliest, now);
        final list = key == null ? null : lookup(key);
        final ride = _choose(section, list, choices[i], earliest);

        final DateTime departure;
        final DateTime arrival;
        if (ride != null) {
          departure = ride.departure.time;
          arrival = ride.arrivalAt ?? departure.add(Duration(seconds: section.duration));
        } else {
          departure = section.departure.isBefore(earliest.subtract(_tolerance)) ? earliest : section.departure;
          arrival = departure.add(Duration(seconds: section.duration));
        }
        sections[i] = _moved(section, departure, arrival, ride);
        if (key != null) {
          rides[i] = RidePlan(key: key, ride: ride, earliest: earliest);
        }

        if (i == firstRide && from == 0) {
          // Leave so as to get there when it leaves
          var end = departure;
          for (var k = i - 1; k >= 0; k--) {
            final before = sections[k];
            final start = before.kind == SectionKind.wait ? end : end.subtract(Duration(seconds: before.duration));
            sections[k] = _moved(before, start, end, null);
            end = start;
          }
        } else if (waitIndex != null) {
          final wait = sections[waitIndex];
          sections[waitIndex] = _moved(wait, wait.departure, departure.isBefore(wait.departure) ? wait.departure : departure, null);
        }
        waitIndex = null;
        cursor = arrival;
      case SectionKind.wait:
        sections[i] = _moved(section, cursor, cursor, null);
        waitIndex = i;
      default:
        final end = cursor.add(Duration(seconds: section.duration));
        sections[i] = _moved(section, cursor, end, null);
        cursor = end;
    }
  }

  final departure = sections.first.departure;
  final arrival = sections.last.arrival;
  return RetimedJourney(
    journey.copyWith(
      sections: sections,
      departure: departure,
      arrival: arrival,
      duration: arrival.difference(departure).inSeconds,
    ),
    rides,
  );
}

/// When the traveller can be at the boarding stop of the ride [index] of [journey]: end of the section before it
/// (waits aside), now for a first section
DateTime earliestBoarding(JourneyOption journey, int index, DateTime now) => _lastEnd(journey.sections, index) ?? now;

DateTime? _lastEnd(List<JourneySection> sections, int index) {
  for (var k = index - 1; k >= 0; k--) {
    if (sections[k].kind != SectionKind.wait) {
      return sections[k].arrival;
    }
  }
  return null;
}

int _walkingBefore(List<JourneySection> sections, int index) => sections
    .take(index)
    .where((section) => section.kind != SectionKind.wait)
    .fold(0, (total, section) => total + section.duration);

Ride? _choose(JourneySection section, List<Ride>? list, Ride? choice, DateTime earliest) {
  if (choice != null) {
    // Its latest real time
    return list?.where((ride) => sameRide(ride, choice)).firstOrNull ?? choice;
  }
  if (list == null) {
    return null;
  }
  final catchable = earliest.subtract(_tolerance);
  final planned = plannedRide(list, section.departure);
  if (planned != null && !planned.departure.cancelled && !planned.departure.time.isBefore(catchable)) {
    return planned;
  }
  return list.where((ride) => !ride.departure.cancelled && !ride.departure.time.isBefore(catchable)).firstOrNull;
}

/// The departure planned at [planned]: closest scheduled time, a few minutes off at most
Ride? plannedRide(List<Ride> rides, DateTime planned) {
  Ride? best;
  var bestGap = const Duration(minutes: 4);
  for (final ride in rides) {
    final gap = (ride.departure.aimedTime ?? ride.departure.time).difference(planned).abs();
    if (gap <= bestGap) {
      bestGap = gap;
      best = ride;
    }
  }
  return best;
}

/// [section] moved to [departure] → [arrival], its stop times spread the same way; a ride gets the real-time state
/// of the departure taken
JourneySection _moved(JourneySection section, DateTime departure, DateTime arrival, Ride? ride) {
  if (departure == section.departure && arrival == section.arrival && ride == null) {
    return section;
  }
  final oldSpan = section.arrival.difference(section.departure).inSeconds;
  final newSpan = arrival.difference(departure).inSeconds;
  DateTime? stopTime(DateTime? time) {
    if (time == null) {
      return null;
    }
    final ratio = oldSpan <= 0 ? 0.0 : time.difference(section.departure).inSeconds / oldSpan;
    return departure.add(Duration(seconds: (ratio * newSpan).round()));
  }

  return section.copyWith(
    departure: departure,
    arrival: arrival,
    duration: newSpan,
    stops: [for (final stop in section.stops) stop.copyWith(time: stopTime(stop.time))],
    headsign: ride?.destination ?? section.headsign,
    realtime: ride == null ? section.realtime : ride.departure.realtime,
    delay: ride == null
        ? section.delay
        : ride.departure.aimedTime == null
        ? null
        : ride.departure.time.difference(ride.departure.aimedTime!).inSeconds,
  );
}

/// [journey] with the sections from [from] on moved by [by]
JourneyOption shiftJourney(JourneyOption journey, {required int from, required Duration by}) {
  final sections = [
    for (final (index, section) in journey.sections.indexed)
      index < from ? section : _moved(section, section.departure.add(by), section.arrival.add(by), null),
  ];
  return journey.copyWith(
    sections: sections,
    arrival: sections.last.arrival,
    duration: sections.last.arrival.difference(journey.departure).inSeconds,
  );
}
