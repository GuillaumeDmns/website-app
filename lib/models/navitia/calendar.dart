import 'calendar_exc.dart';
import 'calendar_period.dart';
import 'validity_pattern.dart';
import 'week_pattern.dart';

class Calendar {
  final List<CalendarPeriod>? activePeriods;
  final String? name;
  final ValidityPattern? validityPattern;
  final List<CalendarExc>? exceptions;
  final WeekPattern? weekPattern;
  final String? id;

  Calendar({
    this.activePeriods,
    this.name,
    this.validityPattern,
    this.exceptions,
    this.weekPattern,
    this.id,
  });

  factory Calendar.fromJson(Map<String, dynamic> json) {
    return Calendar(
      activePeriods: (json['active_periods'] as List?)
          ?.map((e) => CalendarPeriod.fromJson(e))
          .toList(),
      name: json['name'] as String?,
      validityPattern: json['validity_pattern'] != null
          ? ValidityPattern.fromJson(json['validity_pattern'])
          : null,
      exceptions: (json['exceptions'] as List?)
          ?.map((e) => CalendarExc.fromJson(e))
          .toList(),
      weekPattern: json['week_pattern'] != null
          ? WeekPattern.fromJson(json['week_pattern'])
          : null,
      id: json['id'] as String?,
    );
  }
}