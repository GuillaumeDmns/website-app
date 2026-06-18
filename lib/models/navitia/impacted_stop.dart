import 'stop_point.dart';
import 'stop_time_effect.dart';

class ImpactedStop {
  final String? amendedArrivalTime;
  final StopPoint? stopPoint;
  final StopTimeEffect? stopTimeEffect;
  final String? departureStatus;
  final bool? isDetour;
  final String? amendedDepartureTime;
  final String? baseArrivalTime;
  final String? cause;
  final String? baseDepartureTime;
  final String? arrivalStatus;

  ImpactedStop({
    this.amendedArrivalTime,
    this.stopPoint,
    this.stopTimeEffect,
    this.departureStatus,
    this.isDetour,
    this.amendedDepartureTime,
    this.baseArrivalTime,
    this.cause,
    this.baseDepartureTime,
    this.arrivalStatus,
  });

  factory ImpactedStop.fromJson(Map<String, dynamic> json) {
    return ImpactedStop(
      amendedArrivalTime: json['amended_arrival_time'] as String?,
      stopPoint: json['stop_point'] != null
          ? StopPoint.fromJson(json['stop_point'])
          : null,
      stopTimeEffect: json['stop_time_effect'] as StopTimeEffect?,
      departureStatus: json['departure_status'] as String?,
      isDetour: json['is_detour'] as bool?,
      amendedDepartureTime: json['amended_departure_time'] as String?,
      baseArrivalTime: json['base_arrival_time'] as String?,
      cause: json['cause'] as String?,
      baseDepartureTime: json['base_departure_time'] as String?,
      arrivalStatus: json['arrival_status'] as String?,
    );
  }
}