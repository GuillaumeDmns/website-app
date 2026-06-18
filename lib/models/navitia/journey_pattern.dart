import 'route.dart';

class JourneyPattern {
  final String? id;
  final String? name;
  final Route? route;

  JourneyPattern({
    this.id,
    this.name,
    this.route,
  });

  factory JourneyPattern.fromJson(Map<String, dynamic> json) {
    return JourneyPattern(
      id: json['id'] as String?,
      name: json['name'] as String?,
      route: json['route'] != null ? Route.fromJson(json['route']) : null,
    );
  }
}
