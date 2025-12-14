import 'stop_point.dart';

class StopDateTime {
  final StopPoint? stopPoint;

  final String? arrivalDateTime;

  final String? departureDateTime;

  final String? baseArrivalDateTime;

  final String? baseDepartureDateTime;

  StopDateTime(
      {this.stopPoint,
      this.arrivalDateTime,
      this.departureDateTime,
      this.baseArrivalDateTime,
      this.baseDepartureDateTime});

  factory StopDateTime.fromJson(Map<String, dynamic> json) {
    return StopDateTime(
      stopPoint: json['stopPoint'] != null
          ? StopPoint.fromJson(json['stopPoint'])
          : null,
      arrivalDateTime: json['arrivalDateTime'] as String?,
      departureDateTime: json['departureDateTime'] as String?,
      baseArrivalDateTime: json['baseArrivalDateTime'] as String?,
      baseDepartureDateTime: json['baseDepartureDateTime'] as String?,
    );
  }
}
