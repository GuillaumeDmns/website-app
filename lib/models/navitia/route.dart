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
      isFrequence: json['isFrequence'] != null
          ? IsFrequenceEnum.values.firstWhere(
              (e) => e.value == json['isFrequence'].toString(),
              orElse: () => IsFrequenceEnum.false_,
            )
          : null,
      directionType: json['directionType'] as String?,
      physicalModes: (json['physicalModes'] as List?)
          ?.map((e) => PhysicalMode.fromJson(e as Map<String, dynamic>))
          .toList(),
      comments: (json['comments'] as List?)
          ?.map((e) => Comment.fromJson(e as Map<String, dynamic>))
          .toList(),
      codes: (json['codes'] as List?)
          ?.map((e) => Code.fromJson(e as Map<String, dynamic>))
          .toList(),
      direction: json['direction'] != null
          ? Place.fromJson(json['direction'] as Map<String, dynamic>)
          : null,
      geojson: json['geojson'] != null
          ? MultiLineStringSchema.fromJson(json['geojson'] as Map<String, dynamic>)
          : null,
      links: (json['links'] as List?)
          ?.map((e) => LinkSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
      line: json['line'] != null
          ? Line.fromJson(json['line'] as Map<String, dynamic>)
          : null,
      stopPoints: (json['stopPoints'] as List?)
          ?.map((e) => StopPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
