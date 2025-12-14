import 'coord.dart';

class Admin {
  final String? insee;
  final String? name;
  final int? level;
  final Coord? coord;
  final String? label;
  final String? id;
  final String? zipCode;

  Admin(
      {this.insee,
      this.name,
      this.level,
      this.coord,
      this.label,
      this.id,
      this.zipCode});

  factory Admin.fromJson(Map<String, dynamic> json) {
    return Admin(
      insee: json['insee'] as String?,
      name: json['name'] as String?,
      level: json['level'] as int?,
      coord: Coord.fromJson(json['coord']),
      label: json['label'] as String?,
      id: json['id'] as String?,
      zipCode: json['zipCode'] as String?,
    );
  }
}
