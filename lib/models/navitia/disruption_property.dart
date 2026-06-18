class DisruptionProperty {
  final String? type;
  final String? key;
  final String? value;

  DisruptionProperty({
    this.type,
    this.key,
    this.value,
  });

  factory DisruptionProperty.fromJson(Map<String, dynamic> json) {
    return DisruptionProperty(
      type: json['type'] as String?,
      key: json['key'] as String?,
      value: json['value'] as String?,
    );
  }
}
