class CalendarExc {
  final String? type;
  final String? datetime;

  CalendarExc({
    this.type,
    this.datetime,
  });

  factory CalendarExc.fromJson(Map<String, dynamic> json) {
    return CalendarExc(
      type: json['type'] as String?,
      datetime: json['datetime'] as String?,
    );
  }
}
