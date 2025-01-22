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
      commercialMode: json['commercialMode'] != null
          ? CommercialMode.fromJson(json['commercialMode'])
          : null,
      physicalModes: json['physicalModes'] != null
          ? (json['physicalModes'] as List<dynamic>)
              .map((physicalMode) =>
                  PhysicalMode.fromJson(physicalMode as Map<String, dynamic>))
              .toList()
          : null,
      routes: json['routes'] != null
          ? (json['routes'] as List<dynamic>)
              .map((route) => Route.fromJson(route as Map<String, dynamic>))
              .toList()
          : null,
      network:
          json['network'] != null ? Network.fromJson(json['network']) : null,
      closingTime: json['closingTime'] as String?,
      openingTime: json['openingTime'] as String?,
      properties: json['properties'] != null
          ? (json['properties'] as List<dynamic>)
              .map((property) =>
                  Property.fromJson(property as Map<String, dynamic>))
              .toList()
          : null,
      geojson: json['geojson'] != null
          ? MultiLineStringSchema.fromJson(json['geojson'])
          : null,
      links: json['links'] != null
          ? (json['links'] as List<dynamic>)
              .map((link) => LinkSchema.fromJson(link as Map<String, dynamic>))
              .toList()
          : null,
      lineGroups: json['lineGroups'] != null
          ? (json['lineGroups'] as List<dynamic>)
              .map((lineGroup) =>
                  LineGroup.fromJson(lineGroup as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
