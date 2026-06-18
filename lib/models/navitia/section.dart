import 'boarding_position.dart';
import 'path.dart';
import 'place.dart';
import 'section_display_information.dart';
import 'section_geojson_schema.dart';
import 'stop_date_time.dart';
import 'via.dart';

class Section {
  final Place? from;
  final String? transferType;
  final String? arrivalDateTime;
  final String? departureDateTime;
  final Place? to;
  final SectionGeoJsonSchema? geojson;
  final int? duration;
  final List<Path>? path;
  final List<StopDateTime>? stopDateTimes;
  final String? type;
  final String? id;
  final String? dataFreshness;
  final String? mode;
  final List<BoardingPositionEnum>? bestBoardingPositions;
  final SectionDisplayInformation? displayInformations;
  final List<Via>? vias;

  Section({
    this.from,
    this.transferType,
    this.arrivalDateTime,
    this.departureDateTime,
    this.to,
    this.geojson,
    this.duration,
    this.path,
    this.stopDateTimes,
    this.type,
    this.id,
    this.dataFreshness,
    this.mode,
    this.bestBoardingPositions,
    this.displayInformations,
    this.vias,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      from: json['from'] != null ? Place.fromJson(json['from']) : null,
      transferType: json['transferType'] as String?,
      arrivalDateTime: json['arrivalDateTime'] as String?,
      departureDateTime: json['departureDateTime'] as String?,
      to: json['to'] != null ? Place.fromJson(json['to']) : null,
      geojson: json['geojson'] != null
          ? SectionGeoJsonSchema.fromJson(json['geojson'])
          : null,
      duration: json['duration'] as int?,
      path: json['path'] != null
          ? (json['path'] as List<dynamic>)
              .map((place) => Path.fromJson(place))
              .toList()
          : null,
      stopDateTimes: json['stopDateTimes'] != null
          ? (json['stopDateTimes'] as List<dynamic>)
              .map((place) => StopDateTime.fromJson(place))
              .toList()
          : null,
      type: json['type'] as String?,
      id: json['id'] as String?,
      dataFreshness: json['dataFreshness'] as String?,
      mode: json['mode'] as String?,
      bestBoardingPositions: json['bestBoardingPositions'] != null
          ? (json['bestBoardingPositions'] as List<dynamic>)
              .map((position) => BoardingPositionEnum.values
                  .firstWhere((e) => e.value == position))
              .toList()
          : null,
      displayInformations: json['displayInformations'] != null
          ? SectionDisplayInformation.fromJson(json['displayInformations'])
          : null,
      vias: json['vias'] != null
          ? (json['vias'] as List<dynamic>)
              .map((place) => Via.fromJson(place))
              .toList()
          : null,
    );
  }

  Section copyWith({
    Place? from,
    String? transferType,
    String? arrivalDateTime,
    String? departureDateTime,
    Place? to,
    SectionGeoJsonSchema? geojson,
    int? duration,
    List<Path>? path,
    List<StopDateTime>? stopDateTimes,
    String? type,
    String? id,
    String? dataFreshness,
    String? mode,
    List<BoardingPositionEnum>? bestBoardingPositions,
    SectionDisplayInformation? displayInformations,
    List<Via>? vias,
  }) {
    return Section(
      from: from ?? this.from,
      transferType: transferType ?? this.transferType,
      arrivalDateTime: arrivalDateTime ?? this.arrivalDateTime,
      departureDateTime: departureDateTime ?? this.departureDateTime,
      to: to ?? this.to,
      geojson: geojson ?? this.geojson,
      duration: duration ?? this.duration,
      path: path ?? this.path,
      stopDateTimes: stopDateTimes ?? this.stopDateTimes,
      type: type ?? this.type,
      id: id ?? this.id,
      dataFreshness: dataFreshness ?? this.dataFreshness,
      mode: mode ?? this.mode,
      bestBoardingPositions:
          bestBoardingPositions ?? this.bestBoardingPositions,
      displayInformations: displayInformations ?? this.displayInformations,
      vias: vias ?? this.vias,
    );
  }
}
