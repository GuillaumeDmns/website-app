class CommercialMode {
  final String? id;
  final String? name;

  CommercialMode({this.id, this.name});

  factory CommercialMode.fromJson(Map<String, dynamic> json) {
    return CommercialMode(
      id: json['id'] as String?,
      name: json['name'] as String?,
    );
  }
}
