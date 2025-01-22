import 'code.dart';
import 'comment.dart';
import 'commercial_mode.dart';
import 'line_group.dart';
import 'link_schema.dart';
import 'multi_line_string_schema.dart';
import 'network.dart';
import 'physical_mode.dart';
import 'property.dart';
import 'route.dart';

class Line {
  final String? id;
  final String? name;
  final String? code;
  final String? color;
  final String? textColor;
  final List<Comment>? comments;
  final String? comment;
  final List<Code>? codes;
  final CommercialMode? commercialMode;
  final List<PhysicalMode>? physicalModes;
  final List<Route>? routes;
  final Network? network;
  final String? closingTime;
  final String? openingTime;
  final List<Property>? properties;
  final MultiLineStringSchema? geojson;
  final List<LinkSchema>? links;
  final List<LineGroup>? lineGroups;

  Line(
      {this.id,
      this.name,
      this.code,
      this.color,
      this.textColor,
      this.comments,
      this.comment,
      this.codes,
      this.commercialMode,
      this.physicalModes,
      this.routes,
      this.network,
      this.closingTime,
      this.openingTime,
      this.properties,
      this.geojson,
      this.links,
      this.lineGroups});

  factory Line.fromJson(Map<String, dynamic> json) {
    return Line(
      id: json['id'] as String?,
      name: json['name'] as String?,
      code: json['code'] as String?,
      color: json['color'] as String?,
      textColor: json['textColor'] as String?,
      comments: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((comment) => Comment.fromJson(comment)))
          .toList(),
      comment: json['comment'] as String?,
      codes: (json['code'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((code) => Code.fromJson(code)))
          .toList(),
      commercialMode: CommercialMode.fromJson(json['commercialMode']),
      physicalModes: (json['physicalModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List)
              .map((physicalMode) => PhysicalMode.fromJson(physicalMode)))
          .toList(),
      routes: (json['routes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((route) => Route.fromJson(route)))
          .toList(),
      network: Network.fromJson(json['network']),
      closingTime: json['closingTime'] as String?,
      openingTime: json['openingTime'] as String?,
      properties: (json['properties'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List)
              .map((property) => Property.fromJson(property)))
          .toList(),
      geojson: MultiLineStringSchema.fromJson(json['geojson']),
      links: (json['links'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((link) => LinkSchema.fromJson(link)))
          .toList(),
      lineGroups: (json['lineGroups'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List)
              .map((lineGroup) => LineGroup.fromJson(lineGroup)))
          .toList(),
    );
  }
}
