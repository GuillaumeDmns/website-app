import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/geo.dart';
import '../auth/auth_controller.dart';
import '../journey/journey_request.dart';
import '../journey/journey_retime.dart';

/// A trip made often ("Maison → Travail"), kept on this device: a journey option found once by a search, then
/// retimed with the departures of its lines (`/lines/{id}/rides`), never searched again (no Navitia call).
class DailyTrip {
  const DailyTrip({required this.id, required this.journey, required this.request});

  /// When it was saved (milliseconds), unique on the device
  final String id;

  /// The option as found, its times aside: its walks and rides
  final JourneyOption journey;

  /// The search it comes from ("Ma position" replaced by where it starts), to look for other options
  final JourneyRequest request;

  JourneyPoint? get from => journey.sections.firstOrNull?.from;

  JourneyPoint? get to => journey.sections.lastOrNull?.to;

  /// Where it starts as searched (a saved place, an address…), else its first point
  JourneyPoint? get start => _searched(request.from) ?? from;

  /// Where it ends as searched, else its last point
  JourneyPoint? get end => _searched(request.to) ?? to;

  static JourneyPoint? _searched(JourneyPlace? place) => place == null || place.isCurrentLocation || place.lat == null
      ? null
      : JourneyPoint(name: place.name, lat: place.lat!, lon: place.lon!, stopAreaId: place.stopAreaId);

  /// Line ids of its rides, which tell two trips apart
  String get lines => journey.rides.map((ride) => ride.line?.id ?? '').join(',');

  /// The way back, on the same lines
  DailyTrip reversed() => DailyTrip(id: id, journey: reverseJourney(journey), request: request.swapped());

  Map<String, dynamic> toJson() => {'id': id, 'journey': journey.toJson(), 'request': request.toQuery()};

  static DailyTrip? fromJson(Map<String, dynamic> json) {
    try {
      return DailyTrip(
        id: json['id'] as String,
        journey: JourneyOption.fromJson(json['journey'] as Map<String, dynamic>),
        request: JourneyRequest.fromQuery((json['request'] as Map<String, dynamic>).cast<String, String>()),
      );
    } catch (_) {
      // Model changed since it was saved
      return null;
    }
  }

  /// [journey] kept without what changes each time (real time, walking instructions are kept)
  static DailyTrip of(JourneyOption journey, JourneyRequest request, {required DateTime now}) => DailyTrip(
        id: '${now.millisecondsSinceEpoch}',
        journey: journey.copyWith(
          sections: [
            for (final section in journey.sections) section.copyWith(realtime: null, delay: null),
          ],
        ),
        request: request.forSharing(journey).copyWith(datetime: () => null, arriveBy: false),
      );
}

/// Trips done often, saved on this device (cleared at sign-out like the other copies of an account's data)
class DailyTrips extends AsyncNotifier<List<DailyTrip>> {
  static const key = 'daily_trips';

  /// Shown on the home page, at most
  static const max = 5;

  @override
  Future<List<DailyTrip>> build() async {
    ref.watch(authControllerProvider);
    final json = await ref.read(localStoreProvider).readJson(key);
    if (json is! List) {
      return const [];
    }
    return [
      for (final item in json)
        if (item is Map<String, dynamic>) ?DailyTrip.fromJson(item),
    ];
  }

  /// The saved trip [journey] makes (same start, end and lines), either way: the way back of a trip is shown with it
  DailyTrip? find(JourneyOption journey) {
    final from = journey.sections.firstOrNull?.from;
    final to = journey.sections.lastOrNull?.to;
    final lines = journey.rides.map((ride) => ride.line?.id ?? '').toList();
    bool close(JourneyPoint? a, JourneyPoint? b) =>
        a != null && b != null && metersBetween(LatLng(a.lat, a.lon), LatLng(b.lat, b.lon)) < 150;
    return state.value?.where((trip) {
      final same = trip.lines == lines.join(',') && close(trip.from, from) && close(trip.to, to);
      final back = trip.lines == lines.reversed.join(',') && close(trip.from, to) && close(trip.to, from);
      return same || back;
    }).firstOrNull;
  }

  Future<void> save(JourneyOption journey, JourneyRequest request, {DateTime? now}) async {
    final existing = find(journey);
    final trip = DailyTrip.of(journey, request, now: now ?? DateTime.now());
    final next = [
      ...?state.value?.where((other) => other.id != existing?.id),
      trip,
    ].reversed.take(max).toList().reversed.toList();
    await _write(next);
  }

  Future<void> remove(DailyTrip trip) => _write([...?state.value?.where((other) => other.id != trip.id)]);

  Future<void> _write(List<DailyTrip> trips) async {
    state = AsyncData(trips);
    await ref.read(localStoreProvider).writeJson(key, trips.map((trip) => trip.toJson()).toList());
  }
}

final dailyTripsProvider = AsyncNotifierProvider<DailyTrips, List<DailyTrip>>(DailyTrips.new);

/// [journey] the other way: sections in reverse order, each from its end to its start, with the same durations
/// (walking instructions and boarding positions, which depend on the way, left out; the destination of a ride comes
/// with its departures)
JourneyOption reverseJourney(JourneyOption journey) {
  var cursor = journey.departure;
  final sections = <JourneySection>[];
  for (final section in journey.sections.reversed) {
    final end = cursor.add(Duration(seconds: section.duration));
    sections.add(section.copyWith(
      departure: cursor,
      arrival: end,
      from: section.to,
      to: section.from,
      headsign: null,
      boardingPositions: const [],
      steps: const [],
      stops: [
        for (final stop in section.stops.reversed) stop.copyWith(time: null),
      ],
      shape: section.shape.reversed.toList(),
      realtime: null,
      delay: null,
    ));
    cursor = end;
  }
  return journey.copyWith(sections: sections, departure: journey.departure, arrival: cursor);
}

/// The next ways of making [trip] from [now]: the first departure its first ride can catch, then the following
/// ones of that ride, each with the connections it gets (see [retimeJourney]); at most [count]
List<JourneyOption> upcomingTrips(JourneyOption trip, {required RideLookup lookup, required DateTime now, int count = 3}) {
  final first = retimeJourney(trip, lookup: lookup, now: now);
  final index = trip.sections.indexWhere((section) => section.kind == SectionKind.transit);
  final plan = first.rides[index];
  final taken = plan?.ride;
  final list = plan == null ? null : lookup(plan.key);
  if (taken == null || list == null) {
    return [first.journey];
  }
  final later = list
      .where((ride) => !ride.departure.cancelled && ride.departure.time.isAfter(taken.departure.time))
      .take(count - 1);
  return [
    first.journey,
    for (final ride in later) retimeJourney(trip, lookup: lookup, now: now, choices: {index: ride}).journey,
  ];
}

/// Below this gap between a service day's last ride and the next day's first, the line runs all night: no last one
const _allNight = Duration(hours: 1);

/// The latest time to leave the start of a trip tonight, from the last rides of its lines
class LastTripAlert {
  const LastTripAlert({this.leaveBy, this.resumesAt, required this.ride, this.lastDeparture});

  /// Null when it is too late tonight
  final DateTime? leaveBy;

  /// When the trip can be made again (the first rides of the next service day), when known
  final DateTime? resumesAt;

  /// The ride whose last departure sets [leaveBy] (or the one not running any more)
  final JourneySection ride;

  /// That ride's last departure from its stop
  final DateTime? lastDeparture;

  bool get over => leaveBy == null;
}

/// When [trip] must start at the latest tonight given the last rides of its lines ([spans], by section: null while
/// unknown), or null when no ride has a last one (lines running all night, unknown spans). Each ride is reached from
/// the start of the trip in the time its sections before take (waits aside).
LastTripAlert? lastTripAlert(JourneyOption trip, RideSpan? Function(JourneySection ride) spans, DateTime now) {
  var offset = Duration.zero;
  final legs = <({JourneySection ride, Duration offset, RideSpan span})>[];
  for (final section in trip.sections) {
    if (section.kind == SectionKind.transit) {
      final span = spans(section);
      if (span != null) {
        legs.add((ride: section, offset: offset, span: span));
      }
    }
    if (section.kind != SectionKind.wait) {
      offset += Duration(seconds: section.duration);
    }
  }

  DateTime? resumes() {
    DateTime? latest;
    for (final leg in legs) {
      final first = leg.span.first;
      final next = leg.span.next;
      // The first ride ahead: today's when it hasn't started yet, else tomorrow's
      final ahead = first != null && first.departure.isAfter(now) ? first : next;
      if (ahead == null) {
        return null;
      }
      final start = ahead.departure.subtract(leg.offset);
      latest = latest == null || start.isAfter(latest) ? start : latest;
    }
    return latest;
  }

  ({JourneySection ride, DateTime leaveBy, DateTime last})? limit;
  for (final leg in legs) {
    final span = leg.span;
    final first = span.first;
    final last = span.last;
    // Not running yet: tonight's service is over for this ride
    if (first != null && first.departure.subtract(leg.offset).isAfter(now) && first.departure.isAfter(now)) {
      return LastTripAlert(ride: leg.ride, resumesAt: resumes());
    }
    if (last == null) {
      continue;
    }
    final next = span.next;
    if (next != null && next.departure.difference(last.departure) < _allNight) {
      continue;
    }
    final leaveBy = last.departure.subtract(leg.offset);
    if (limit == null || leaveBy.isBefore(limit.leaveBy)) {
      limit = (ride: leg.ride, leaveBy: leaveBy, last: last.departure);
    }
  }
  if (limit == null) {
    return null;
  }
  if (limit.leaveBy.isBefore(now)) {
    return LastTripAlert(ride: limit.ride, lastDeparture: limit.last, resumesAt: resumes());
  }
  return LastTripAlert(leaveBy: limit.leaveBy, ride: limit.ride, lastDeparture: limit.last);
}
