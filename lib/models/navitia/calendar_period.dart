class CalendarPeriod {
  final String? begin;
  final String? end;

  CalendarPeriod({
    this.begin,
    this.end,
  });

  factory CalendarPeriod.fromJson(Map<String, dynamic> json) {
    return CalendarPeriod(
      begin: json['begin'] as String?,
      end: json['end'] as String?,
    );
  }
}
