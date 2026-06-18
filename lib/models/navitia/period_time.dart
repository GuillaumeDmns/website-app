class PeriodTime {
  final String? begin;
  final String? end;

  PeriodTime({
    this.begin,
    this.end,
  });

  factory PeriodTime.fromJson(Map<String, dynamic> json) {
    return PeriodTime(
      begin: json['begin'] as String?,
      end: json['end'] as String?,
    );
  }
}
