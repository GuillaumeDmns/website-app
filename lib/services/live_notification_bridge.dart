import 'package:flutter/services.dart';
import 'dart:async';
import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';

class LiveNotificationBridge {
  static const MethodChannel _channel =
      MethodChannel('com.guillaumedamiens.live_notification/bridge');

  Future<void> updateJourneyProgress({
    required Journey journey,
    required double distanceTraveledMeters,
    required int currentSectionIndex,
  }) async {
    final sections = journey.sections!;

    final segmentsPayload = sections
        .where((s) =>
            !["crow_fly", "waiting", "transfer"].contains(s.type) &&
            (s.geojson?.properties?[0].length ?? 0) > 0)
        .map((section) {
      return {
        'length': section.geojson?.properties?[0].length ?? 0,
        'color': _getHexColorForSection(section),
        'type': section.type ?? 'unknown',
      };
    }).toList();

    String currentMode = "default";
    Section? currentSection;

    if (currentSectionIndex >= 0 && currentSectionIndex < sections.length) {
      currentSection = sections[currentSectionIndex];
      currentMode = _getSectionMode(currentSection);
    }

    int remainingSeconds = 0;
    for (int i = currentSectionIndex; i < sections.length; i++) {
      remainingSeconds += sections[i].duration ?? 0;
    }
    String remainingTimeStr = "${(remainingSeconds / 60).ceil()} min";

    String chipText = _generateShortChipText(currentSection, remainingTimeStr);

    String longInfo = _generateLongInfoText(currentSection, remainingTimeStr);

    try {
      await _channel.invokeMethod('updateJourney', {
        'title': "Trip to ${sections.lastOrNull?.to?.name ?? 'Destination'}",
        'status': _buildStatusText(journey, distanceTraveledMeters),
        'progress': distanceTraveledMeters.toInt(),
        'currentMode': currentMode,
        'remainingTime': remainingTimeStr,
        'chipText': chipText,
        'longInfo': longInfo,
        'segments': segmentsPayload,
      });
    } on PlatformException catch (e) {
      print("Bridge Error: ${e.message}");
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopNotification');
    } catch (e) {
      print(e);
    }
  }

  String _generateShortChipText(Section? section, String timeStr) {
    if (section == null) return timeStr;

    String currentMode = _getSectionMode(section);
    String code = section.displayInformations?.code ?? "";

    switch (currentMode) {
      case 'RER':
        return "RER $code";
      case 'Train Transilien':
        return "Train $code";
      case 'TER':
        return "TER";
      case 'Métro':
        return "Métro $code";
      case 'Tramway':
        return "Tram $code";
      case 'Bus':
      case 'public_transport':
      case 'vehicle':
        return "Bus $code";
      case 'transfer':
        return "Transfer";
      case 'crow_fly':
        return "Crowfly";
      case 'waiting':
        return "Wait";
      case 'walking':
        return 'Walk';
      default:
        return timeStr.replaceAll(" min", "'");
    }
  }

  String _generateLongInfoText(Section? section, String timeStr) {
    if (section == null) return timeStr;

    String modePart = "";
    if (section.mode == "walking") {
      modePart = "Walk";
    } else if (section.displayInformations != null) {
      modePart =
          "${section.displayInformations!.commercialMode} ${section.displayInformations!.code}";
    }

    if (modePart.isNotEmpty) {
      return "$modePart • $timeStr";
    }
    return timeStr;
  }

  String _getHexColorForSection(Section section) {
    if (section.displayInformations?.color != null) {
      return "#${section.displayInformations!.color}";
    }
    return "#D3D3D3";
  }

  String _buildStatusText(Journey journey, double distTraveled) {
    String distStr = (distTraveled > 1000)
        ? "${(distTraveled / 1000).toStringAsFixed(1)} km"
        : "${distTraveled.toInt()} m";
    return "$distStr traveled";
  }

  String _getSectionMode(Section section) {
    return section.displayInformations?.commercialMode ??
        section.mode ??
        section.type ??
        "default";
  }
}
