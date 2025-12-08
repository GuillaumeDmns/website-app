import 'equipments.dart';
import 'link_schema.dart';

class SectionDisplayInformation {
  final String? direction;
  final String? code;
  final String? network;
  final List<LinkSchema>? links;
  final String? color;
  final String? name;
  final String? physicalMode;
  final String? headsign;
  final String? label;
  final List<EquipmentsEnum>? equipments;
  final String? textColor;
  final List<String>? headsigns;
  final String? commercialMode;
  final String? description;
  final String? tripShortName;
  final String? company;

  SectionDisplayInformation(
      {this.direction,
      this.code,
      this.network,
      this.links,
      this.color,
      this.name,
      this.physicalMode,
      this.headsign,
      this.label,
      this.equipments,
      this.textColor,
      this.headsigns,
      this.commercialMode,
      this.description,
      this.tripShortName,
      this.company});

  factory SectionDisplayInformation.fromJson(Map<String, dynamic> json) {
    return SectionDisplayInformation(
      direction: json['direction'] as String?,
      code: json['code'] as String?,
      network: json['network'] as String?,
      links: (json['links'] as List<dynamic>?)
          ?.map((code) => LinkSchema.fromJson(code))
          .toList(),
      color: json['color'] as String?,
      name: json['name'] as String?,
      physicalMode: json['physicalMode'] as String?,
      headsign: json['headsign'] as String?,
      label: json['label'] as String?,
      // equipments: (json['equipments'] as List<dynamic>?)
      //     ?.map((code) => EquipmentsEnum..fromJson(code))
      //     .toList(),
      textColor: json['textColor'] as String?,
      headsigns: (json['headsigns'] as List<dynamic>?)
              ?.map((code) => code as String)
              .toList() ??
          [],
      commercialMode: json['commercialMode'] as String?,
      description: json['description'] as String?,
      tripShortName: json['tripShortName'] as String?,
      company: json['company'] as String?,
    );
  }
}
