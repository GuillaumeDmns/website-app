class Trip {
  final String? id;
  final String? name;

  Trip({
    this.id,
    this.name,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String?,
      name: json['name'] as String?,
    );
  }
}
