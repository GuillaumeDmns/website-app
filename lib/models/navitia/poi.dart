import 'address.dart';
import 'admin.dart';
import 'car_park.dart';
import 'coord.dart';
import 'link_schema.dart';
import 'poi_type.dart';
import 'stands.dart';

class Poi {
  final String? id;
  final String? name;
  final Coord? coord;
  final List<LinkSchema>? links;
  final String? label;
  final List<Admin>? administrativeRegions;
  final PoiType? poiType;
  final Map<String, String>? properties;
  final Address? address;
  final Stands? stands;
  final CarPark? carPark;

  Poi(
      {this.id,
      this.name,
      this.coord,
      this.links,
      this.label,
      this.administrativeRegions,
      this.poiType,
      this.properties,
      this.address,
      this.stands,
      this.carPark});

  factory Poi.fromJson(Map<String, dynamic> json) {
    return Poi(
      id: json['id'] as String?,
      name: json['name'] as String?,
      coord: json['coord'] != null ? Coord.fromJson(json['coord']) : null,
      links: json['links'] != null
          ? (json['links'] as List)
              .map((link) => LinkSchema.fromJson(link as Map<String, dynamic>))
              .toList()
          : null,
      label: json['label'] as String?,
      administrativeRegions: json['administrativeRegions'] != null
          ? (json['administrativeRegions'] as List)
              .map((admin) => Admin.fromJson(admin as Map<String, dynamic>))
              .toList()
          : null,
      poiType:
          json['poiType'] != null ? PoiType.fromJson(json['poiType']) : null,
      properties: json['properties'] != null
          ? Map<String, String>.from(json['properties'] as Map)
          : null,
      address:
          json['address'] != null ? Address.fromJson(json['address']) : null,
      stands: json['stands'] != null ? Stands.fromJson(json['stands']) : null,
      carPark:
          json['carPark'] != null ? CarPark.fromJson(json['carPark']) : null,
    );
  }
}
