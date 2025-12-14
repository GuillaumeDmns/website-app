import 'admin.dart';
import 'coord.dart';

class Address {
  final String? name;
  final int? houseNumber;
  final Coord? coord;
  final String? label;
  final List<Admin>? administrativeRegions;
  final String? id;

  Address(
      {this.name,
      this.houseNumber,
      this.coord,
      this.label,
      this.administrativeRegions,
      this.id});

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      name: json['name'] as String?,
      houseNumber: json['house_number'] as int?,
      coord: json['coord'] != null ? Coord.fromJson(json['coord']) : null,
      label: json['label'] as String?,
      administrativeRegions: json['administrativeRegions'] != null
          ? (json['administrativeRegions'] as List)
          .map((region) => Admin.fromJson(region as Map<String, dynamic>))
          .toList()
          : null,
      id: json['id'] as String?,
    );
  }

}
