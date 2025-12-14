class PoiType {
  final String? id;
  final String? name;

  PoiType({this.id, this.name});

  factory PoiType.fromJson(Map<String, dynamic> json) {
    return PoiType(
      id: json['id'] as String?,
      name: json['name'] as String?,
    );
  }
}

