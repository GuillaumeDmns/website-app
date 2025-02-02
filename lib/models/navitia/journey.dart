import 'durations.dart';
import 'section.dart';

class Journey {
  final int? nbTransfers;

  final Durations? durations;

  final String? arrivalDateTime;

  final String? departureDateTime;

  final String? requestedDateTime;

  final int? duration;

  final List<Section>? sections;

  Journey(
      {this.nbTransfers,
      this.durations,
      this.arrivalDateTime,
      this.departureDateTime,
      this.requestedDateTime,
      this.duration,
      this.sections});

  factory Journey.fromJson(Map<String, dynamic> json) {
    return Journey(
      nbTransfers: json['nbTransfers'] as int?,
      durations: json['durations'] != null
          ? Durations.fromJson(json['durations'])
          : null,
      arrivalDateTime: json['arrivalDateTime'] as String?,
      departureDateTime: json['departureDateTime'] as String?,
      requestedDateTime: json['requestedDateTime'] as String?,
      duration: json['duration'] as int?,
      sections: json['sections'] != null
          ? (json['sections'] as List<dynamic>)
              .map((place) => Section.fromJson(place))
              .toList()
          : null,
    );
  }
}
