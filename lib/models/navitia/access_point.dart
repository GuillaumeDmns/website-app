import 'coord.dart';

class AccessPoint {
  final String? id;
  final String? name;
  final Coord? coord;
  final String? accessPointCode;

  // final EmbeddedTypeEnum? embeddedType;
  final String? embeddedType;

  AccessPoint(
      {this.id,
      this.name,
      this.coord,
      this.accessPointCode,
      this.embeddedType});

  factory AccessPoint.fromJson(Map<String, dynamic> json) {
    return AccessPoint(
      id: json['id'] as String?,
      name: json['name'] as String?,
      coord: json['coord'] != null ? Coord.fromJson(json['coord']) : null,
      accessPointCode: json['accessPointCode'] as String?,
      embeddedType: json['embeddedType'] as String?,
      // embeddedType: json['embeddedType'] != null
      //     ? EmbeddedTypeEnum.values.firstWhere(
      //         (e) => e.value == json['embeddedType'],
      //         orElse: () => throw Exception(
      //             "Invalid embeddedType value: ${json['embeddedType']}"),
      //       )
      //     : null,
    );
  }
}
