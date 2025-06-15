import 'package:website_app/models/navitia/journey.dart';

class Journeys {
  final List<Journey>? journeys;

  Journeys({this.journeys});

  factory Journeys.fromJson(Map<String, dynamic> json) {
    return Journeys(
      journeys: json['journeys'] != null
          ? (json['journeys'] as List<dynamic>)
              .map((place) => Journey.fromJson(place))
              .toList()
          : null,
    );
  }
}
