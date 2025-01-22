import 'package:website_app/models/navitia/equipments.dart';
import 'package:website_app/models/navitia/physical_mode.dart';
import 'package:website_app/models/navitia/stop_area.dart';

import 'address.dart';
import 'admin.dart';
import 'code.dart';
import 'comment.dart';
import 'commercial_mode.dart';
import 'coord.dart';
import 'equipment_details.dart';
import 'fare_zone.dart';
import 'line.dart';
import 'link_schema.dart';

class StopPoint {
  final String? id;
  final String? name;
  final List<Comment>? comments;
  final String? comment;
  final List<Code>? codes;
  final String? label;
  final Coord? coord;
  final List<LinkSchema>? links;
  final List<CommercialMode>? commercialModes;
  final List<PhysicalMode>? physicalModes;
  final List<Admin>? administrativeRegions;
  final StopArea? stopArea;
  final List<EquipmentsEnum>? equipments;
  final Address? address;
  final FareZone? fareZone;
  final List<EquipmentDetails>? equipmentDetails;
  final List<Line>? lines;

  // final List<PathWay> accessPoints;

  StopPoint(
      {this.id,
      this.name,
      this.comments,
      this.comment,
      this.codes,
      this.label,
      this.coord,
      this.links,
      this.commercialModes,
      this.physicalModes,
      this.administrativeRegions,
      this.stopArea,
      this.equipments,
      this.address,
      this.fareZone,
      this.equipmentDetails,
      this.lines});

  factory StopPoint.fromJson(Map<String, dynamic> json) {
    return StopPoint(
      id: json['id'] as String?,
      name: json['name'] as String?,
      comments: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((comment) => Comment.fromJson(comment)))
          .toList(),
      comment: json['comment'] as String?,
      codes: (json['codes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((code) => Code.fromJson(code)))
          .toList(),
      label: json['label'] as String?,
      coord: Coord.fromJson(json['coord']),
      links: (json['links'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((link) => LinkSchema.fromJson(link)))
          .toList(),
      commercialModes: (json['commercialModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List)
              .map((mode) => CommercialMode.fromJson(mode)))
          .toList(),
      physicalModes: (json['physicalModes'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((mode) => PhysicalMode.fromJson(mode)))
          .toList(),
      administrativeRegions:
          (json['administrativeRegions'] as Map<String, dynamic>)
              .entries
              .expand((entry) =>
                  (entry.value as List).map((region) => Admin.fromJson(region)))
              .toList(),
      stopArea: StopArea.fromJson(json['stopArea']),
      equipments: (json['equipments'] as List<dynamic>?)
          ?.map((equipment) => EquipmentsEnum.values.firstWhere(
                (e) => e.toString() == 'EquipmentsEnum.$equipment',
              ))
          .cast<EquipmentsEnum>()
          .toList(),
      address: Address.fromJson(json['address']),
      fareZone: FareZone.fromJson(json['fare_zone']),
      equipmentDetails: (json['equipmentDetails'] as Map<String, dynamic>)
          .entries
          .expand((entry) => (entry.value as List).map(
              (equipmentDetail) => EquipmentDetails.fromJson(equipmentDetail)))
          .toList(),
      lines: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((line) => Line.fromJson(line)))
          .toList(),
    );
  }
}
