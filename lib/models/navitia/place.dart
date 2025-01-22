import 'address.dart';
import 'admin.dart';
import 'embedded_type.dart';
import 'poi.dart';
import 'stop_area.dart';
import 'stop_point.dart';

class Place {
  final String? id;
  final String? name;
  final int? quality;
  final StopArea? stopArea;
  final StopPoint? stopPoint;
  final Admin? administrativeRegion;
  final EmbeddedTypeEnum? embeddedType;
  final Address? address;
  final Poi? poi;
  final String? distance;

  // final PathWay? accessPoint;

  Place(
      {this.id,
      this.name,
      this.quality,
      this.stopArea,
      this.stopPoint,
      this.administrativeRegion,
      this.embeddedType,
      this.address,
      this.poi,
      this.distance});

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String?,
      name: json['name'] as String?,
      quality: json['quality'] as int?,
      stopArea:
          json['stopArea'] != null ? StopArea.fromJson(json['stopArea']) : null,
      stopPoint: json['stopPoint'] != null
          ? StopPoint.fromJson(json['stopPoint'])
          : null,
      administrativeRegion: json['administrativeRegion'] != null
          ? Admin.fromJson(json['administrativeRegion'])
          : null,
      embeddedType: json['embeddedType'] != null
          ? EmbeddedTypeEnum.values.firstWhere(
              (e) => e.value == json['embeddedType'],
              orElse: () => throw Exception(
                  "Invalid embeddedType value: ${json['embeddedType']}"),
            )
          : null,
      address:
          json['address'] != null ? Address.fromJson(json['address']) : null,
      poi: json['poi'] != null ? Poi.fromJson(json['poi']) : null,
      distance: json['distance'] as String?,
    );
  }
}
