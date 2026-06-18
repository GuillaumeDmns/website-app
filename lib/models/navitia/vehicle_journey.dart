import 'calendar.dart';
import 'code.dart';
import 'disruption.dart';
import 'journey_pattern.dart';
import 'stop_time.dart';
import 'trip.dart';
import 'validity_pattern.dart';

class VehicleJourney {
  final String? id;
  final String? name;
  final JourneyPattern? journeyPattern;
  final List<StopTime>? stopTimes;
  final List<Code>? codes;
  final ValidityPattern? validityPattern;
  final List<Calendar>? calendars;
  final Trip? trip;
  final List<Disruption>? disruptions;
  final String? headsign;

  VehicleJourney({
    this.id,
    this.name,
    this.journeyPattern,
    this.stopTimes,
    this.codes,
    this.validityPattern,
    this.calendars,
    this.trip,
    this.disruptions,
    this.headsign,
  });

  factory VehicleJourney.fromJson(Map<String, dynamic> json) {
    return VehicleJourney(
      id: json['id'] as String?,
      name: json['name'] as String?,
      journeyPattern: json['journey_pattern'] != null
          ? JourneyPattern.fromJson(json['journey_pattern'] as Map<String, dynamic>)
          : null,
      stopTimes: (json['stop_times'] as List?)
          ?.map((e) => StopTime.fromJson(e as Map<String, dynamic>))
          .toList(),
      codes: (json['codes'] as List?)
          ?.map((e) => Code.fromJson(e as Map<String, dynamic>))
          .toList(),
      validityPattern: json['validity_pattern'] != null
          ? ValidityPattern.fromJson(json['validity_pattern'] as Map<String, dynamic>)
          : null,
      calendars: (json['calendars'] as List?)
          ?.map((e) => Calendar.fromJson(e))
          .toList(),
      trip: json['trip'] != null ? Trip.fromJson(json['trip']) : null,
      disruptions: (json['disruptions'] as List?)
          ?.map((e) => Disruption.fromJson(e))
          .toList(),
      headsign: json['headsign'] as String?,
    );
  }
}