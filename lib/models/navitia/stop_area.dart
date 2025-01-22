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
      comments: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((comment) => Comment.fromJson(comment)))
          .toList(),
      comment: json['comment'] as String?,
      codes: (json['codes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((code) => Code.fromJson(code)))
          .toList(),
      timezone: json['timezone'] as String?,
      label: json['label'] as String?,
      coord: Coord.fromJson(json['coord']),
      links: (json['links'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((link) => LinkSchema.fromJson(link)))
          .toList(),
      commercialModes: (json['commercialModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List)
              .map((mode) => CommercialMode.fromJson(mode)))
          .toList(),
      physicalModes: (json['physicalModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((mode) => PhysicalMode.fromJson(mode)))
          .toList(),
      administrativeRegions:
          (json['administrativeRegions'] as Map<String, dynamic>)
              .entries
              .expand((entry) =>
                  (entry.value as List).map((admin) => Admin.fromJson(admin)))
              .toList(),
      stopPoints: (json['stopPoints'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((stop) => StopPoint.fromJson(stop)))
          .toList(),
      lines: (json['lines'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((line) => Line.fromJson(line)))
          .toList(),
    );
  }
}
