import 'package:website_app/models/navitia/place.dart';

class Places {
  final List<Place>? places;

  // TODO other fields

  Places({this.places});

  factory Places.fromJson(Map<String, dynamic> json) {
    return Places(
      places: (json['places'] as List<dynamic>)
          .map((place) => Place.fromJson(place))
          .toList(),
    );
  }
}
