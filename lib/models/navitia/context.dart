class Context {
  final String? currentDatetime;
  final String? timezone;

  Context({this.currentDatetime, this.timezone});

  factory Context.fromJson(Map<String, dynamic> json) {
    return Context(
      currentDatetime: json['currentDatetime'] as String?,
      timezone: json['timezone'] as String?,
    );
  }
}
