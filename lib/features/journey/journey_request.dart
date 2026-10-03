import 'package:flutter/foundation.dart';

import '../../core/api/models.dart';

/// Start or end of a journey: the user position, a stop area or a point.
@immutable
class JourneyPlace {
  const JourneyPlace._({required this.name, this.lat, this.lon, this.stopAreaId, this.isCurrentLocation = false});

  const JourneyPlace.currentLocation() : this._(name: 'Ma position', isCurrentLocation: true);

  const JourneyPlace.point({required String name, required double lat, required double lon})
      : this._(name: name, lat: lat, lon: lon);

  const JourneyPlace.stopArea({required String name, required String id, double? lat, double? lon})
      : this._(name: name, stopAreaId: id, lat: lat, lon: lon);

  factory JourneyPlace.fromPlace(PlaceResult place) => place.type == PlaceType.stopArea
      ? JourneyPlace.stopArea(name: place.name, id: place.id, lat: place.lat, lon: place.lon)
      : JourneyPlace.point(name: place.name, lat: place.lat, lon: place.lon);

  final String name;
  final double? lat;
  final double? lon;
  final String? stopAreaId;
  final bool isCurrentLocation;

  /// Value of the `from` / `to` URL parameter: `here`, a stop area id or `lat,lon`
  String get param => isCurrentLocation ? 'here' : stopAreaId ?? '${lat!.toStringAsFixed(6)},${lon!.toStringAsFixed(6)}';

  /// Parses [param] (see above); [name] is shown to the user
  static JourneyPlace? parse(String? param, String? name) {
    if (param == null || param.isEmpty) {
      return null;
    }
    if (param == 'here') {
      return const JourneyPlace.currentLocation();
    }
    if (param.startsWith('IDFM:')) {
      return JourneyPlace.stopArea(name: name ?? param, id: param);
    }
    final parts = param.split(',');
    final lat = parts.length == 2 ? double.tryParse(parts[0]) : null;
    final lon = parts.length == 2 ? double.tryParse(parts[1]) : null;
    return lat == null || lon == null ? null : JourneyPlace.point(name: name ?? 'Point sur la carte', lat: lat, lon: lon);
  }

  @override
  bool operator ==(Object other) => other is JourneyPlace && other.param == param;

  @override
  int get hashCode => param.hashCode;
}

enum WalkingSpeed {
  slow('Lente'),
  normal('Normale'),
  fast('Rapide');

  const WalkingSpeed(this.label);

  final String label;

  String get apiName => name.toUpperCase();
}

/// Everything that defines a journey search; it is kept in the URL so that results can be shared or reloaded.
@immutable
class JourneyRequest {
  const JourneyRequest({
    this.from,
    this.to,
    this.datetime,
    this.arriveBy = false,
    this.modes = const {},
    this.wheelchair = false,
    this.walkingSpeed = WalkingSpeed.normal,
  });

  final JourneyPlace? from;
  final JourneyPlace? to;

  /// Null: leave now
  final DateTime? datetime;
  final bool arriveBy;

  /// Allowed modes, all when empty
  final Set<TransportMode> modes;
  final bool wheelchair;
  final WalkingSpeed walkingSpeed;

  bool get isComplete => from != null && to != null;

  /// Options other than the defaults
  int get optionCount => (modes.isEmpty ? 0 : 1) + (wheelchair ? 1 : 0) + (walkingSpeed == WalkingSpeed.normal ? 0 : 1);

  JourneyRequest copyWith({
    JourneyPlace? from,
    JourneyPlace? to,
    DateTime? Function()? datetime,
    bool? arriveBy,
    Set<TransportMode>? modes,
    bool? wheelchair,
    WalkingSpeed? walkingSpeed,
  }) =>
      JourneyRequest(
        from: from ?? this.from,
        to: to ?? this.to,
        datetime: datetime != null ? datetime() : this.datetime,
        arriveBy: arriveBy ?? this.arriveBy,
        modes: modes ?? this.modes,
        wheelchair: wheelchair ?? this.wheelchair,
        walkingSpeed: walkingSpeed ?? this.walkingSpeed,
      );

  JourneyRequest swapped() => JourneyRequest(
        from: to,
        to: from,
        datetime: datetime,
        arriveBy: arriveBy,
        modes: modes,
        wheelchair: wheelchair,
        walkingSpeed: walkingSpeed,
      );

  Map<String, String> toQuery() => {
        if (from != null) 'from': from!.param,
        if (from != null && !from!.isCurrentLocation) 'fromName': from!.name,
        if (to != null) 'to': to!.param,
        if (to != null && !to!.isCurrentLocation) 'toName': to!.name,
        if (datetime != null) 'at': datetime!.toUtc().toIso8601String(),
        if (arriveBy) 'arriveBy': '1',
        if (modes.isNotEmpty) 'modes': modes.map((mode) => mode.apiName).join(','),
        if (wheelchair) 'wheelchair': '1',
        if (walkingSpeed != WalkingSpeed.normal) 'walk': walkingSpeed.apiName,
      };

  factory JourneyRequest.fromQuery(Map<String, String> query) => JourneyRequest(
        from: JourneyPlace.parse(query['from'], query['fromName']),
        to: JourneyPlace.parse(query['to'], query['toName']),
        datetime: DateTime.tryParse(query['at'] ?? ''),
        arriveBy: query['arriveBy'] == '1',
        modes: {
          for (final name in (query['modes'] ?? '').split(','))
            ...TransportMode.values.where((mode) => mode.apiName == name),
        },
        wheelchair: query['wheelchair'] == '1',
        walkingSpeed: WalkingSpeed.values.firstWhere((speed) => speed.apiName == query['walk'], orElse: () => WalkingSpeed.normal),
      );

  @override
  bool operator ==(Object other) => other is JourneyRequest && mapEquals(other.toQuery(), toQuery());

  @override
  int get hashCode => Object.hashAllUnordered(toQuery().entries.map((e) => '${e.key}=${e.value}'));
}
