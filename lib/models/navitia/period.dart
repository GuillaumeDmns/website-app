class Period {
  final String? begin;
  final String? end;

  Period({
    this.begin,
    this.end,
  });

  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      begin: json['begin'] as String?,
      end: json['end'] as String?,
    );
  }
}
