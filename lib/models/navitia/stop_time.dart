import 'journey_pattern_point.dart';
import 'stop_point.dart';

class StopTime {
  final String? arrivalTime;
  final String? utcArrivalTime;
  final String? departureTime;
  final String? utcDepartureTime;
  final String? headsign;
  final JourneyPatternPoint? journeyPatternPoint;
  final StopPoint? stopPoint;
  final bool? pickupAllowed;
  final bool? dropOffAllowed;
  final bool? skippedStop;

  StopTime({
    this.arrivalTime,
    this.utcArrivalTime,
    this.departureTime,
    this.utcDepartureTime,
    this.headsign,
    this.journeyPatternPoint,
    this.stopPoint,
    this.pickupAllowed,
    this.dropOffAllowed,
    this.skippedStop,
  });

  factory StopTime.fromJson(Map<String, dynamic> json) {
    return StopTime(
      arrivalTime: json['arrivalTime'] as String?,
      utcArrivalTime: json['utcArrivalTime'] as String?,
      departureTime: json['departureTime'] as String?,
      utcDepartureTime: json['utcDepartureTime'] as String?,
      headsign: json['headsign'] as String?,
      journeyPatternPoint: json['journeyPatternPoint'] != null
          ? JourneyPatternPoint.fromJson(json['journeyPatternPoint'])
          : null,
      stopPoint: json['stopPoint'] != null
          ? StopPoint.fromJson(json['stopPoint'])
          : null,
      pickupAllowed: json['pickupAllowed'] as bool?,
      dropOffAllowed: json['dropOffAllowed'] as bool?,
      skippedStop: json['skipped_stop'] as bool?,
    );
  }
}
