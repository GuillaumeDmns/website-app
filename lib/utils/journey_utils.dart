import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;
import 'package:website_app/models/navitia/journey.dart';
import 'package:website_app/models/navitia/link_schema.dart';
import 'package:website_app/models/navitia/place.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/utils/style_utils.dart';

import '../models/navitia/stop_area.dart';

class ProcessedJourneyData {
  final List<Polyline> polylines;
  final List<LatLng> allJourneyPoints;
  final List<LatLng> fullJourneyPolyline;
  final List<double> cumulativeDistances;
  final double totalJourneyDistanceInMeters;

  ProcessedJourneyData({
    required this.polylines,
    required this.allJourneyPoints,
    required this.fullJourneyPolyline,
    required this.cumulativeDistances,
    required this.totalJourneyDistanceInMeters,
  });
}

class JourneyProgressUpdate {
  final int newSectionIndex;
  final List<Polyline> newPolylines;
  final double traveledDistance;
  final bool isJourneyFinished;

  JourneyProgressUpdate({
    required this.newSectionIndex,
    required this.newPolylines,
    required this.traveledDistance,
    required this.isJourneyFinished,
  });
}

class JourneyUtils {
  static ProcessedJourneyData processJourneyForMap(Journey journey) {
    final List<Polyline> newJourneyPolylines = [];
    final List<LatLng> allJourneyPoints = [];
    final List<LatLng> fullJourneyPolyline = [];
    final List<double> cumulativeDistances = [];
    double totalDistance = 0;

    for (var section in journey.sections!) {
      if (section.geojson != null &&
          section.geojson!.coordinates != null &&
          section.geojson!.coordinates!.isNotEmpty) {
        final List<LatLng> sectionPoints = [];
        for (var coord in section.geojson!.coordinates!) {
          if (coord.length >= 2) {
            final point = LatLng(coord[1], coord[0]);
            sectionPoints.add(point);
            allJourneyPoints.add(point);
            fullJourneyPolyline.add(point);
          }
        }
        if (sectionPoints.isNotEmpty) {
          final color =
              StyleUtils.hexToColor(section.displayInformations?.color);
          newJourneyPolylines.add(
            Polyline(
              points: sectionPoints,
              strokeWidth: 5.0,
              color: color,
            ),
          );
        }
      }
      totalDistance += section.geojson?.properties?[0].length ?? 0;
      cumulativeDistances.add(totalDistance);
    }

    return ProcessedJourneyData(
      polylines: newJourneyPolylines,
      allJourneyPoints: allJourneyPoints,
      fullJourneyPolyline: fullJourneyPolyline,
      cumulativeDistances: cumulativeDistances,
      totalJourneyDistanceInMeters: totalDistance,
    );
  }

  static JourneyProgressUpdate updateJourneyProgress({
    required Position position,
    required Journey activeJourney,
    required List<LatLng> fullJourneyPolyline,
    required List<double> cumulativeDistances,
  }) {
    final userPosition = turf.Position(position.longitude, position.latitude);

    int newSectionIndex = -1;
    double minDistanceToSection = double.infinity;

    for (int i = 0; i < activeJourney.sections!.length; i++) {
      final section = activeJourney.sections![i];
      if (section.geojson?.coordinates == null ||
          section.geojson!.coordinates!.isEmpty) {
        continue;
      }

      final sectionPoints = section.geojson!.coordinates!
          .where((c) => c.length >= 2)
          .map((c) => turf.Position(c[0], c[1]))
          .toList();

      if (sectionPoints.isEmpty) continue;

      final sectionLine = turf.LineString(coordinates: sectionPoints);
      final pointOnThisSection = turf.nearestPointOnLine(
          sectionLine, turf.Point(coordinates: userPosition), turf.Unit.meters);
      final distance = pointOnThisSection.properties!['dist'] as num;

      if (distance < minDistanceToSection) {
        minDistanceToSection = distance.toDouble();
        newSectionIndex = i;
      }
    }

    if (newSectionIndex == -1) {
      newSectionIndex = activeJourney.sections!.length - 1;
    }

    final newPolylines = <Polyline>[];
    for (int i = 0; i < activeJourney.sections!.length; i++) {
      final section = activeJourney.sections![i];
      if (section.geojson?.coordinates == null ||
          section.geojson!.coordinates!.isEmpty) {
        continue;
      }

      final sectionPoints = section.geojson!.coordinates!
          .where((c) => c.length >= 2)
          .map((c) => LatLng(c[1], c[0]))
          .toList();

      if (sectionPoints.isEmpty) continue;

      final originalColor =
          StyleUtils.hexToColor(section.displayInformations?.color);
      final traveledColor = originalColor.withValues(alpha: 0.2);

      if (i < newSectionIndex) {
        newPolylines.add(Polyline(
            points: sectionPoints, strokeWidth: 5.0, color: traveledColor));
      } else if (i > newSectionIndex) {
        newPolylines.add(Polyline(
            points: sectionPoints, strokeWidth: 5.0, color: originalColor));
      } else {
        final sectionLine = turf.LineString(
            coordinates: sectionPoints
                .map((p) => turf.Position(p.longitude, p.latitude))
                .toList());
        final snappedOnSection = turf.nearestPointOnLine(sectionLine,
            turf.Point(coordinates: userPosition), turf.Unit.meters);
        final snappedLatLngOnSection = LatLng(
            snappedOnSection.geometry!.coordinates.lat.toDouble(),
            snappedOnSection.geometry!.coordinates.lng.toDouble());
        final splitIndex = snappedOnSection.properties!['index'] as int;

        if (splitIndex >= 0 && sectionPoints.length > 1) {
          final traveledPart = sectionPoints.sublist(0, splitIndex + 1)
            ..add(snappedLatLngOnSection);
          newPolylines.add(Polyline(
              points: traveledPart, strokeWidth: 5.0, color: traveledColor));
        }

        if (splitIndex < sectionPoints.length - 1) {
          final remainingPart = [
            snappedLatLngOnSection,
            ...sectionPoints.sublist(splitIndex + 1)
          ];
          newPolylines.add(Polyline(
              points: remainingPart, strokeWidth: 5.0, color: originalColor));
        } else if (newPolylines
                .where((p) => p.color == originalColor)
                .isEmpty &&
            sectionPoints.length <= 1) {
          newPolylines.add(Polyline(
              points: [snappedLatLngOnSection, sectionPoints.last],
              strokeWidth: 5.0,
              color: originalColor));
        }
      }
    }

    double traveledDistance = 0;
    if (newSectionIndex > 0) {
      traveledDistance += cumulativeDistances[newSectionIndex - 1];
    }

    final currentSectionPoints = activeJourney
        .sections![newSectionIndex].geojson!.coordinates!
        .where((c) => c.length >= 2)
        .map((c) => LatLng(c[1], c[0]))
        .toList();

    final snappedOnSection = turf.nearestPointOnLine(
        turf.LineString(
            coordinates: currentSectionPoints
                .map((p) => turf.Position(p.longitude, p.latitude))
                .toList()),
        turf.Point(
            coordinates: turf.Position(position.longitude, position.latitude)),
        turf.Unit.meters);
    final splitIndex = snappedOnSection.properties!['index'] as int;
    final snappedLatLngOnSection = LatLng(
        snappedOnSection.geometry!.coordinates.lat.toDouble(),
        snappedOnSection.geometry!.coordinates.lng.toDouble());

    double distanceInCurrentSection = 0.0;
    for (int i = 0; i < splitIndex; i++) {
      distanceInCurrentSection += Geolocator.distanceBetween(
        currentSectionPoints[i].latitude,
        currentSectionPoints[i].longitude,
        currentSectionPoints[i + 1].latitude,
        currentSectionPoints[i + 1].longitude,
      );
    }

    if (splitIndex < currentSectionPoints.length) {
      distanceInCurrentSection += Geolocator.distanceBetween(
        currentSectionPoints[splitIndex].latitude,
        currentSectionPoints[splitIndex].longitude,
        snappedLatLngOnSection.latitude,
        snappedLatLngOnSection.longitude,
      );
    }
    traveledDistance += distanceInCurrentSection;

    final endPoint = fullJourneyPolyline.last;
    final distanceToEnd = Geolocator.distanceBetween(position.latitude,
        position.longitude, endPoint.latitude, endPoint.longitude);
    final bool isJourneyFinished = distanceToEnd < 50;

    return JourneyProgressUpdate(
      newSectionIndex: newSectionIndex,
      newPolylines: newPolylines,
      traveledDistance: traveledDistance,
      isJourneyFinished: isJourneyFinished,
    );
  }

  static String getSectionTitle(Section section, List<StopArea> terminusList) {
    final displayInfos = section.displayInformations;
    if (displayInfos != null) {
      String title;
      if (displayInfos.commercialMode == "TER") {
        title = displayInfos.name ?? "TER";
      } else {
        title = displayInfos.commercialMode ?? "";
        if (displayInfos.label != null && displayInfos.label!.isNotEmpty) {
          title += " ${displayInfos.label}";
        }
      }

      if (displayInfos.direction != null &&
          displayInfos.direction!.isNotEmpty) {
        title += _getTerminus(
            terminusList, displayInfos.links, displayInfos.direction);
      }

      return title.isEmpty ? "Transport line" : title;
    }

    if (section.mode != null) {
      switch (section.mode) {
        case 'walking':
          return "Walk to ${getPlaceBeautifulName(section.to, "destination")}";
        default:
          return "Travel by ${_capitalize(section.mode!)}";
      }
    }

    if (section.type != null) {
      String durationStr = section.duration != null
          ? " (~ ${(section.duration! / 60).ceil()} min)"
          : "";

      switch (section.type) {
        case 'transfer':
          return "Transfer at ${getPlaceBeautifulName(section.to, "stop")}";
        case 'waiting':
          return "Wait for connection at ${getPlaceBeautifulName(section.to, "station")}$durationStr";
        default:
          return _capitalize(section.type!);
      }
    }

    return "Journey step";
  }

  static String getPlaceBeautifulName(Place? place, String defaultName) {
    if (place == null) return defaultName;

    final name = place.stopPoint?.name ?? place.stopArea?.name ?? place.name;

    return name ?? defaultName;
  }

  static String _capitalize(String input) {
    if (input.isEmpty) return input;
    final formatted = input.replaceAll('_', ' ');
    return "${formatted[0].toUpperCase()}${formatted.substring(1)}";
  }

  static String _getTerminus(
      List<StopArea> terminusList, List<LinkSchema>? links, String? direction) {
    LinkSchema? terminusLink;
    try {
      terminusLink = links?.firstWhere((link) => link.rel == "terminus");
    } catch (_) {
      terminusLink = null;
    }

    if (terminusLink != null && terminusLink.id != null) {
      StopArea? matchingStop;
      try {
        matchingStop =
            terminusList.firstWhere((stop) => stop.id == terminusLink!.id);
      } catch (_) {
        matchingStop = null;
      }

      if (matchingStop != null && matchingStop.name != null) {
        return " direction ${matchingStop.name}";
      }
    }

    if (direction != null && direction.isNotEmpty) {
      return " direction $direction";
    }

    return "";
  }
}
