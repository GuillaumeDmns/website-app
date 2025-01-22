class Property {
  final String? type;
  final String? value;

  Property({this.type, this.value});

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      type: json['type'] as String?,
      value: json['value'] as String?,
    );
  }
}
