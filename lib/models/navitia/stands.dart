import 'package:website_app/models/navitia/status.dart';

class Stands {
  final int? availablePlaces;
  final int? availableBikes;
  final int? totalStands;
  final StatusEnum? status;

  Stands(
      {this.availablePlaces,
      this.availableBikes,
      this.totalStands,
      this.status});

  factory Stands.fromJson(Map<String, dynamic> json) {
    return Stands(
      availablePlaces: json['availablePlaces'] as int?,
      availableBikes: json['availableBikes'] as int?,
      totalStands: json['totalStands'] as int?,
      status: json['status'] as StatusEnum?,
    );
  }
}
