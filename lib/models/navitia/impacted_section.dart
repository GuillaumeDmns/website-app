import 'pt_object.dart';
import 'route.dart';

class ImpactedSection {
  final PtObject? from;
  final PtObject? to;
  final List<Route>? routes;

  ImpactedSection({
    this.from,
    this.to,
    this.routes,
  });

  factory ImpactedSection.fromJson(Map<String, dynamic> json) {
    return ImpactedSection(
      from: json['from'] != null ? PtObject.fromJson(json['from']) : null,
      to: json['to'] != null ? PtObject.fromJson(json['to']) : null,
      routes: (json['routes'] as List?)?.map((e) => Route.fromJson(e)).toList(),
    );
  }
}
