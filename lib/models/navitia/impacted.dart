import 'impacted_section.dart';
import 'impacted_stop.dart';
import 'pt_object.dart';

class Impacted {
  final PtObject? ptObject;
  final List<ImpactedStop>? impactedStops;
  final ImpactedSection? impactedSection;
  final ImpactedSection? impactedRailSection;

  Impacted({
    this.ptObject,
    this.impactedStops,
    this.impactedSection,
    this.impactedRailSection,
  });

  factory Impacted.fromJson(Map<String, dynamic> json) {
    return Impacted(
      ptObject: json['pt_object'] != null
          ? PtObject.fromJson(json['pt_object'])
          : null,
      impactedStops: (json['impacted_stops'] as List?)
          ?.map((e) => ImpactedStop.fromJson(e))
          .toList(),
      impactedSection: json['impacted_section'] != null
          ? ImpactedSection.fromJson(json['impacted_section'])
          : null,
      impactedRailSection: json['impacted_rail_section'] != null
          ? ImpactedSection.fromJson(json['impacted_rail_section'])
          : null,
    );
  }
}
