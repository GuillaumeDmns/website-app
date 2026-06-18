import 'stop_point.dart';

class JourneyPatternPoint {
  final String? id;
  final StopPoint? stopPoint;

  JourneyPatternPoint({
    this.id,
    this.stopPoint,
  });

  factory JourneyPatternPoint.fromJson(Map<String, dynamic> json) {
    return JourneyPatternPoint(
      id: json['id'] as String?,
      stopPoint: json['stop_point'] != null
          ? StopPoint.fromJson(json['stop_point'])
          : null,
    );
  }
}
