class ValidityPattern {
  final String? beginningDate;
  final String? days;

  ValidityPattern({
    this.beginningDate,
    this.days,
  });

  factory ValidityPattern.fromJson(Map<String, dynamic> json) {
    return ValidityPattern(
      beginningDate: json['beginning_date'] as String?,
      days: json['days'] as String?,
    );
  }
}