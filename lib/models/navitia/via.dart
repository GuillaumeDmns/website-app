import 'access_point.dart';

class Via {
  final String? id;
  final String? name;
  final AccessPoint? accessPoint;
  final bool? isEntrance;
  final bool? isExit;
  final int? length;
  final int? lon;
  final int? traversalTime;
  final int? pathwayMode;

  Via(
      {this.id,
      this.name,
      this.accessPoint,
      this.isEntrance,
      this.isExit,
      this.length,
      this.lon,
      this.traversalTime,
      this.pathwayMode});

  factory Via.fromJson(Map<String, dynamic> json) {
    return Via(
      id: json['id'] as String?,
      name: json['name'] as String?,
      accessPoint: json['accessPoint'] != null
          ? AccessPoint.fromJson(json['accessPoint'])
          : null,
      isEntrance: json['isEntrance'] as bool?,
      isExit: json['isExit'] as bool?,
      length: json['length'] as int?,
      lon: json['lon'] as int?,
      traversalTime: json['traversalTime'] as int?,
      pathwayMode: json['pathwayMode'] as int?,
    );
  }
}
