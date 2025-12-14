import 'package:website_app/models/navitia/journey.dart';
import 'package:website_app/models/navitia/stop_area.dart';

class JourneysResponse {
  final List<Journey>? journeys;

  final List<StopArea>? terminus;

  JourneysResponse({this.journeys, this.terminus});

  factory JourneysResponse.fromJson(Map<String, dynamic> json) {
    return JourneysResponse(
      journeys: json['journeys'] != null
          ? (json['journeys'] as List<dynamic>)
              .map((place) => Journey.fromJson(place))
              .toList()
          : null,
      terminus: json['terminus'] != null
          ? (json['terminus'] as List<dynamic>)
              .map((terminus) => StopArea.fromJson(terminus))
              .toList()
          : null,
    );
  }
}
