class FareZone {
  final String? name;

  FareZone({this.name});

  factory FareZone.fromJson(Map<String, dynamic> json) {
    return FareZone(
      name: json['name'] as String?,
    );
  }
}
