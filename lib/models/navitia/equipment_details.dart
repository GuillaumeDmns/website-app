import 'embedded_equipment_details_type.dart';

class EquipmentDetails {
  final String? id;
  final String? name;
  final EmbeddedEquipmentDetailsTypeEnum? embeddedType;

  // final CurrentAvailability? currentAvailability;

  EquipmentDetails({this.id, this.name, this.embeddedType});

  factory EquipmentDetails.fromJson(Map<String, dynamic> json) {
    return EquipmentDetails(
      id: json['id'] as String?,
      name: json['name'] as String?,
      embeddedType: json['embedded_type'] as EmbeddedEquipmentDetailsTypeEnum?,
    );
  }
}
