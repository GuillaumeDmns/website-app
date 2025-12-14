import 'code.dart';
import 'comment.dart';
import 'is_frequence.dart';
import 'line.dart';
import 'link_schema.dart';
import 'multi_line_string_schema.dart';
import 'physical_mode.dart';
import 'place.dart';
import 'stop_point.dart';

class Route {
  final String? id;
  final String? name;
  final IsFrequenceEnum? isFrequence;
  final String? directionType;
  final List<PhysicalMode>? physicalModes;
  final List<Comment>? comments;
  final List<Code>? codes;
  final Place? direction;
  final MultiLineStringSchema? geojson;
  final List<LinkSchema>? links;
  final Line? line;
  final List<StopPoint>? stopPoints;

  Route(
      {this.id,
      this.name,
      this.isFrequence,
      this.directionType,
      this.physicalModes,
      this.comments,
      this.codes,
      this.direction,
      this.geojson,
      this.links,
      this.line,
      this.stopPoints});

  factory Route.fromJson(Map<String, dynamic> json) {
    return Route(
      id: json['id'] as String?,
      name: json['name'] as String?,
      isFrequence: json['isFrequence'] as IsFrequenceEnum?,
      directionType: json['directionType'] as String?,
      physicalModes: (json['physicalModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((mode) => PhysicalMode.fromJson(mode)))
          .toList(),
      comments: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((comment) => Comment.fromJson(comment)))
          .toList(),
      codes: (json['codes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((code) => Code.fromJson(code)))
          .toList(),
      direction: Place.fromJson(json['direction']),
      geojson: MultiLineStringSchema.fromJson(json['geojson']),
      links: (json['links'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((link) => LinkSchema.fromJson(link)))
          .toList(),
      line: Line.fromJson(json['line']),
      stopPoints: (json['stopPoints'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((stop) => StopPoint.fromJson(stop)))
          .toList(),
    );
  }
}
