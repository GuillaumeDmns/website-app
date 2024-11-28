class StopsByLineDTO {
  final List<IDFMStopArea> stops;
  final String shape;

  StopsByLineDTO({required this.stops, required this.shape});

  factory StopsByLineDTO.fromJson(Map<String, dynamic> json) {
    return StopsByLineDTO(
      stops: (json['stops'] as List<dynamic>?)
          ?.map((e) => IDFMStopArea.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      shape: json['shape'] ?? '',
    );
  }
}

class IDFMStopArea {
  final String? id;
  final String? name;
  final double? latitude;
  final double? longitude;
  final String? type;

  IDFMStopArea({this.id, this.name, this.latitude, this.longitude, this.type});

  factory IDFMStopArea.fromJson(Map<String, dynamic> json) {
    return IDFMStopArea(
      id: json['id'] as String?,
      name: json['name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      type: json['type'] as String?,
    );
  }
}
