class PhysicalMode {
  final String? id;
  final String? name;

  // final CO2EmissionRate co2EmissionRate;

  PhysicalMode({this.id, this.name});

  factory PhysicalMode.fromJson(Map<String, dynamic> json) {
    return PhysicalMode(
      id: json['id'] as String?,
      name: json['name'] as String?,
    );
  }
}
