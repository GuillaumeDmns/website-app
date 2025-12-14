import 'address.dart';
import 'admin.dart';
import 'code.dart';
import 'comment.dart';
import 'commercial_mode.dart';
import 'coord.dart';
import 'equipments.dart';
import 'equipment_details.dart';
import 'fare_zone.dart';
import 'line.dart';
import 'link_schema.dart';
import 'pathway.dart';
import 'physical_mode.dart';
import 'stop_area.dart';

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
  final List<Pathway>? accessPoints;

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
      this.lines,
      this.accessPoints});

  factory StopPoint.fromJson(Map<String, dynamic> json) {
    return StopPoint(
      id: json['id'] as String?,
      name: json['name'] as String?,
      comments: json['comments'] != null
          ? (json['comments'] as List<dynamic>)
              .map((place) => Comment.fromJson(place))
              .toList()
          : null,
      comment: json['comment'] as String?,
      codes: json['codes'] != null
          ? (json['codes'] as List<dynamic>)
              .map((place) => Code.fromJson(place))
              .toList()
          : null,
      label: json['label'] as String?,
      coord: json['coord'] != null ? Coord.fromJson(json['coord']) : null,
      links: json['links'] != null
          ? (json['links'] as List<dynamic>)
              .map((place) => LinkSchema.fromJson(place))
              .toList()
          : null,
      commercialModes: json['commercialModes'] != null
          ? (json['commercialModes'] as List<dynamic>)
              .map((place) => CommercialMode.fromJson(place))
              .toList()
          : null,
      physicalModes: json['physicalModes'] != null
          ? (json['physicalModes'] as List<dynamic>)
              .map((place) => PhysicalMode.fromJson(place))
              .toList()
          : null,
      administrativeRegions: json['administrativeRegions'] != null
          ? (json['administrativeRegions'] as List<dynamic>)
              .map((place) => Admin.fromJson(place))
              .toList()
          : null,
      stopArea:
          json['stopArea'] != null ? StopArea.fromJson(json['stopArea']) : null,
      // equipments: json['equipments'] != null ? (json['equipments'] as List<dynamic>?)
      //     ?.map((equipment) => EquipmentsEnum.values.firstWhere(
      //           (e) => e.toString() == 'EquipmentsEnum.$equipment',
      //         ))
      //     .cast<EquipmentsEnum>()
      //     .toList() : null,
      address:
          json['address'] != null ? Address.fromJson(json['address']) : null,
      fareZone:
          json['fareZone'] != null ? FareZone.fromJson(json['fareZone']) : null,
      equipmentDetails: json['equipmentDetails'] != null
          ? (json['equipmentDetails'] as List<dynamic>)
              .map((place) => EquipmentDetails.fromJson(place))
              .toList()
          : null,
      lines: json['lines'] != null
          ? (json['lines'] as List<dynamic>)
              .map((place) => Line.fromJson(place))
              .toList()
          : null,
      accessPoints: json['accessPoints'] != null
          ? (json['accessPoints'] as List<dynamic>)
              .map((place) => Pathway.fromJson(place))
              .toList()
          : null,
    );
  }
}
