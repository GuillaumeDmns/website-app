import 'application_pattern.dart';
import 'calendar_exc.dart';
import 'disruption_property.dart';
import 'disruption_status.dart';
import 'impacted.dart';
import 'message.dart';
import 'period.dart';
import 'severity.dart';

class Disruption {
  final String? id;
  final String? disruptionId;
  final String? impactId;
  final List<Period>? applicationPeriods;
  final List<ApplicationPattern>? applicationPatterns;
  final DisruptionStatus? status;
  final String? updatedAt;
  final List<String>? tags;
  final String? cause;
  final String? category;
  final Severity? severity;
  final List<Message>? messages;
  final List<Impacted>? impactedObjects;
  final String? uri;
  final String? disruptionUri;
  final String? contributor;
  final List<DisruptionProperty>? properties;
  final List<CalendarExc>? exceptions;

  Disruption({
    this.id,
    this.disruptionId,
    this.impactId,
    this.applicationPeriods,
    this.applicationPatterns,
    this.status,
    this.updatedAt,
    this.tags,
    this.cause,
    this.category,
    this.severity,
    this.messages,
    this.impactedObjects,
    this.uri,
    this.disruptionUri,
    this.contributor,
    this.properties,
    this.exceptions,
  });

  factory Disruption.fromJson(Map<String, dynamic> json) {
    return Disruption(
      id: json['id'] as String?,
      disruptionId: json['disruption_id'] as String?,
      impactId: json['impact_id'] as String?,
      applicationPeriods: (json['application_periods'] as List?)
          ?.map((e) => Period.fromJson(e))
          .toList(),
      applicationPatterns: (json['application_patterns'] as List?)
          ?.map((e) => ApplicationPattern.fromJson(e))
          .toList(),
      status: json['status'] != null
          ? DisruptionStatus.values.firstWhere(
            (e) => e.value == json['status'],
        orElse: () => DisruptionStatus.unknown,
      )
          : null,
      updatedAt: json['updated_at'] as String?,
      tags: (json['tags'] as List?)?.map((e) => e as String).toList(),
      cause: json['cause'] as String?,
      category: json['category'] as String?,
      severity: json['severity'] != null
          ? Severity.fromJson(json['severity'])
          : null,
      messages: (json['messages'] as List?)
          ?.map((e) => Message.fromJson(e))
          .toList(),
      impactedObjects: (json['impacted_objects'] as List?)
          ?.map((e) => Impacted.fromJson(e))
          .toList(),
      uri: json['uri'] as String?,
      disruptionUri: json['disruption_uri'] as String?,
      contributor: json['contributor'] as String?,
      properties: (json['properties'] as List?)
          ?.map((e) => DisruptionProperty.fromJson(e))
          .toList(),
      exceptions: (json['exceptions'] as List?)
          ?.map((e) => CalendarExc.fromJson(e))
          .toList(),
    );
  }
}