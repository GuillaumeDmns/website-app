class PeriodDate {
  final String? begin;
  final String? end;

  PeriodDate({
    this.begin,
    this.end,
  });

  factory PeriodDate.fromJson(Map<String, dynamic> json) {
    return PeriodDate(
      begin: json['begin'] as String?,
      end: json['end'] as String?,
    );
  }
}
