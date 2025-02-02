import 'section_geojson_schema_properties.dart';

class SectionGeoJsonSchema {
  final String? type;

  final List<SectionGeoJsonSchemaProperties>? properties;

  final List<List<double>>? coordinates;

  SectionGeoJsonSchema({this.type, this.properties, this.coordinates});

  factory SectionGeoJsonSchema.fromJson(Map<String, dynamic> json) {
    return SectionGeoJsonSchema(
      type: json['transferType'] as String?,
      properties: json['properties'] != null
          ? (json['properties'] as List<dynamic>)
              .map((place) => SectionGeoJsonSchemaProperties.fromJson(place))
              .toList()
          : null,
      coordinates: json['coordinates'] != null
          ? (json['coordinates'] as List<dynamic>?)
              ?.map((line) => (line as List<dynamic>)
                  .map((coordinate) => coordinate as double)
                  .toList())
              .toList()
          : null,
    );
  }
}
