import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../l10n/l10n.dart';
import '../stops/stop_screen.dart';

/// A station's way in or out: its number on the signs and its street, else the street alone
String stationAccessName(StationEntrance entrance, {required bool exit}) => switch (entrance.code) {
      final code? => exit ? currentL10n.goExitNamed(code, entrance.name) : currentL10n.goEntranceNamed(code, entrance.name),
      null => entrance.name,
    };

/// A way in or out of a station on a walk, and how far along the walk's path it is
typedef StationAccess = ({StationEntrance entrance, double along});

/// The way out of the station that [walk] (starting in it) really takes: the first of Navitia's [accesses] among the
/// station's [entrances], its path starting there
StationAccess? takenExit(MeasuredPolyline walk, List<StationEntrance> accesses, List<StationEntrance> entrances) =>
    _taken(walk, accesses, entrances);

/// The way into the station that [walk] (ending in it) really takes: the last of Navitia's [accesses] among the
/// station's [entrances]
StationAccess? takenEntrance(MeasuredPolyline walk, List<StationEntrance> accesses, List<StationEntrance> entrances) =>
    _taken(walk, accesses.reversed, entrances);

StationAccess? _taken(MeasuredPolyline walk, Iterable<StationEntrance> accesses, List<StationEntrance> entrances) {
  for (final access in accesses) {
    // The station's own entrance (its wheelchair access), never one of another station the walk goes through
    final entrance = entrances.where((entrance) => entrance.id == access.id).firstOrNull;
    if (entrance == null) {
      continue;
    }
    final projection = walk.project(LatLng(entrance.lat, entrance.lon));
    return projection == null ? null : (entrance: entrance, along: projection.along);
  }
  return null;
}

/// The way out of a station that leaves the least to walk on [walk] (starting in the station): the one from which
/// joining the path, then following it to its end, is the shortest; a guess, when Navitia doesn't say which one its
/// path takes ([takenExit])
StationAccess? bestExit(MeasuredPolyline walk, List<StationEntrance> entrances) => _best(walk, entrances, exit: true);

/// The way into a station that [walk] (ending in the station) reaches first, with the least detour from its path
StationAccess? bestEntrance(MeasuredPolyline walk, List<StationEntrance> entrances) => _best(walk, entrances, exit: false);

StationAccess? _best(MeasuredPolyline walk, List<StationEntrance> entrances, {required bool exit}) {
  if (walk.points.isEmpty) {
    return null;
  }
  StationAccess? best;
  var bestCost = double.infinity;
  for (final entrance in entrances) {
    final projection = walk.project(LatLng(entrance.lat, entrance.lon));
    if (projection == null) {
      continue;
    }
    final cost = projection.distance + (exit ? walk.length - projection.along : projection.along);
    if (cost < bestCost) {
      bestCost = cost;
      best = (entrance: entrance, along: projection.along);
    }
  }
  return best;
}
/// The ways in and out of a station of a journey on the map: all of them (GTFS entrances, from its page), the ones the
/// journey takes (by id: true for a way out, false for a way in), and whether the journey gets out there ([exit]: its
/// ways are named exits)
typedef StationAccesses = ({String stopAreaId, List<StationEntrance> entrances, Map<String, bool> taken, bool exit});

/// Rides whose stations have ways in and out worth showing: the metro's and the trains' (a bus or tram stop has none)
bool _underground(JourneySection section) {
  final mode = section.line?.mode;
  return section.kind == SectionKind.transit && (mode == TransportMode.metro || (mode?.isRail ?? false));
}

/// The ends of [journey]'s metro and train rides it walks to or from: the station, that walk, and whether it gets out
/// there ([exit]) or in. A transfer within a station takes no way in or out: its stations are left out.
List<({String stopAreaId, JourneySection walk, bool exit})> _walkedStations(JourneyOption journey) {
  final sections = journey.sections;
  // The walk next to the ride at [index], waits between them left aside; none for a transfer
  JourneySection? walkBeside(int index, int direction) {
    for (var k = index + direction; k >= 0 && k < sections.length; k += direction) {
      final section = sections[k];
      if (section.kind != SectionKind.wait) {
        return section.kind == SectionKind.walk ? section : null;
      }
    }
    return null;
  }

  return [
    for (final (index, section) in sections.indexed)
      if (_underground(section))
        for (final (stopAreaId, exit) in [(section.from?.stopAreaId, false), (section.to?.stopAreaId, true)])
          if ((stopAreaId, walkBeside(index, exit ? 1 : -1)) case (final stopAreaId?, final walk?))
            (stopAreaId: stopAreaId, walk: walk, exit: exit),
  ];
}

/// The metro and train stations [journey] walks into or out of: where its rides by metro or train start and end,
/// transfers within a station aside
Set<String> journeyStationIds(JourneyOption journey) => {for (final end in _walkedStations(journey)) end.stopAreaId};

/// The GTFS entrances of [journey]'s stations as far as their pages are loaded ([stopAreaProvider], GTFS only,
/// cached by the backend)
Map<String, List<StationEntrance>> watchStationEntrances(WidgetRef ref, JourneyOption journey) => {
      for (final id in journeyStationIds(journey)) id: ref.watch(stopAreaProvider(id)).value?.entrances ?? const [],
    };

/// [journey]'s stations with their ways in and out ([entrancesOf], by stop area), and the ones it takes: the way in
/// of the walk to a ride, the way out of the walk after it, as Navitia's path goes ([takenEntrance], [takenExit]),
/// else the best guess ([bestEntrance], [bestExit]); the stations of a transfer within them left out, their ways never
/// taken
List<StationAccesses> journeyStationAccesses(JourneyOption journey, Map<String, List<StationEntrance>> entrancesOf) {
  final taken = <String, Map<String, bool>>{};
  final exits = <String>{};
  for (final (:stopAreaId, :walk, :exit) in _walkedStations(journey)) {
    final all = entrancesOf[stopAreaId];
    if (all == null || all.isEmpty) {
      continue;
    }
    final station = taken.putIfAbsent(stopAreaId, () => {});
    if (exit) {
      exits.add(stopAreaId);
    }
    final line = MeasuredPolyline(sectionPath(walk));
    final access = exit
        ? takenExit(line, walk.accesses, all) ?? bestExit(line, all)
        : takenEntrance(line, walk.accesses, all) ?? bestEntrance(line, all);
    if (access != null) {
      station[access.entrance.id] = exit;
    }
  }
  return [
    for (final MapEntry(key: stopAreaId, value: ids) in taken.entries)
      (stopAreaId: stopAreaId, entrances: entrancesOf[stopAreaId]!, taken: ids, exit: exits.contains(stopAreaId)),
  ];
}
