import 'admin.dart';
import 'code.dart';
import 'comment.dart';
import 'commercial_mode.dart';
import 'coord.dart';
import 'line.dart';
import 'link_schema.dart';
import 'physical_mode.dart';
import 'stop_point.dart';

class StopArea {
  final String? id;
  final String? name;
  final List<Comment>? comments;
  final String? comment;
  final List<Code>? codes;
  final String? timezone;
  final String? label;
  final Coord? coord;
  final List<LinkSchema>? links;
  final List<CommercialMode>? commercialModes;
  final List<PhysicalMode>? physicalModes;
  final List<Admin>? administrativeRegions;
  final List<StopPoint>? stopPoints;
  final List<Line>? lines;

  StopArea(
      {this.id,
      this.name,
      this.comments,
      this.comment,
      this.codes,
      this.timezone,
      this.label,
      this.coord,
      this.links,
      this.commercialModes,
      this.physicalModes,
      this.administrativeRegions,
      this.stopPoints,
      this.lines});

  factory StopArea.fromJson(Map<String, dynamic> json) {
    return StopArea(
      id: json['id'] as String?,
      name: json['name'] as String?,
      comments: json['comments'] != null
          ? (json['comments'] as List<dynamic>)
              .map((comment) =>
                  Comment.fromJson(comment as Map<String, dynamic>))
              .toList()
          : null,
      comment: json['comment'] as String?,
      codes: json['codes'] != null
          ? (json['codes'] as List<dynamic>)
              .map((code) => Code.fromJson(code as Map<String, dynamic>))
              .toList()
          : null,
      timezone: json['timezone'] as String?,
      label: json['label'] as String?,
      coord: json['coord'] != null ? Coord.fromJson(json['coord']) : null,
      links: json['links'] != null
          ? (json['links'] as List<dynamic>)
              .map((link) => LinkSchema.fromJson(link as Map<String, dynamic>))
              .toList()
          : null,
      commercialModes: json['commercialModes'] != null
          ? (json['commercialModes'] as List<dynamic>)
              .map((mode) =>
                  CommercialMode.fromJson(mode as Map<String, dynamic>))
              .toList()
          : null,
      physicalModes: json['physicalModes'] != null
          ? (json['physicalModes'] as List<dynamic>)
              .map(
                  (mode) => PhysicalMode.fromJson(mode as Map<String, dynamic>))
              .toList()
          : null,
      administrativeRegions: json['administrativeRegions'] != null
          ? (json['administrativeRegions'] as List<dynamic>)
              .map((admin) => Admin.fromJson(admin as Map<String, dynamic>))
              .toList()
          : null,
      stopPoints: json['stopPoints'] != null
          ? (json['stopPoints'] as List<dynamic>)
              .map((stop) => StopPoint.fromJson(stop as Map<String, dynamic>))
              .toList()
          : null,
      lines: json['lines'] != null
          ? (json['lines'] as List<dynamic>)
              .map((line) => Line.fromJson(line as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
