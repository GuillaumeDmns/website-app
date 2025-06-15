class SectionGeoJsonSchemaProperties {
  final num? length;

  SectionGeoJsonSchemaProperties({this.length});

  factory SectionGeoJsonSchemaProperties.fromJson(Map<String, dynamic> json) {
    return SectionGeoJsonSchemaProperties(
      length: json['length'] as num?,
    );
  }
}
