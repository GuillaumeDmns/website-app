import 'severity_effect.dart';

class Severity {
  final String? name;
  final SeverityEffect? effect;
  final String? color;
  final int? priority;

  Severity({
    this.name,
    this.effect,
    this.color,
    this.priority,
  });

  factory Severity.fromJson(Map<String, dynamic> json) {
    return Severity(
      name: json['name'] as String?,
      effect: json['effect'] != null
          ? SeverityEffect.values.firstWhere(
            (e) => e.value == json['effect']
      )
          : null,
      color: json['color'] as String?,
      priority: json['priority'] as int?,
    );
  }
}