import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/utils/style_utils.dart';

import '../models/navitia/journey.dart';

class MapUtils {
  static List<Marker> buildActiveJourneyMarkers(Journey journey) {
    return journey.sections?.expand((section) {
          return (section.stopDateTimes ?? []).map(
            (stopDateTime) => (section, stopDateTime),
          );
        }).map((record) {
          final section = record.$1;
          final lat = double.parse(record.$2.stopPoint!.coord!.lat!);
          final lon = double.parse(record.$2.stopPoint!.coord!.lon!);

          return Marker(
            point: LatLng(lat, lon),
            width: 80,
            height: 80,
            child: Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: StyleUtils.hexToColor(section.displayInformations?.color), width: 2.0),
                ),
              ),
            ),
          );
        }).toList() ??
        [];
  }
}
