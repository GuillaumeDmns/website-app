class MultiLineStringSchema {
  final String? type;
  final List<List<List<double>>>? coordinates;

  MultiLineStringSchema({this.type, this.coordinates});

  factory MultiLineStringSchema.fromJson(Map<String, dynamic> json) {
    return MultiLineStringSchema(
      type: json['type'] as String?,
      coordinates: (json['coordinates'] as List<dynamic>?)
          ?.map((line) => (line as List<dynamic>)
              .map((point) => (point as List<dynamic>)
                  .map((coordinate) => coordinate as double)
                  .toList())
              .toList())
          .toList(),
    );
  }
}
