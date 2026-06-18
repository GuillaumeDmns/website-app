import 'period_date.dart';
import 'period_time.dart';
import 'week_pattern.dart';

class ApplicationPattern {
  final WeekPattern? weekPattern;
  final PeriodDate? applicationPeriod;
  final List<PeriodTime>? timeSlots;

  ApplicationPattern({
    this.weekPattern,
    this.applicationPeriod,
    this.timeSlots,
  });

  factory ApplicationPattern.fromJson(Map<String, dynamic> json) {
    return ApplicationPattern(
      weekPattern: json['week_pattern'] != null
          ? WeekPattern.fromJson(json['week_pattern'])
          : null,
      applicationPeriod: json['application_period'] != null
          ? PeriodDate.fromJson(json['application_period'])
          : null,
      timeSlots: (json['time_slots'] as List?)
          ?.map((e) => PeriodTime.fromJson(e))
          .toList(),
    );
  }
}
