import 'path.dart';
import 'place.dart';
import 'section_geojson_schema.dart';
import 'stop_date_time.dart';

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

  Section(
      {this.from,
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
      this.mode});

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
        mode: json['mode'] as String?);
  }
}
