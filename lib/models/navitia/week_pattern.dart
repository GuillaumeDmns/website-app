class WeekPattern {
  final bool? monday;
  final bool? tuesday;
  final bool? wednesday;
  final bool? thursday;
  final bool? friday;
  final bool? saturday;
  final bool? sunday;

  WeekPattern({
    this.monday,
    this.tuesday,
    this.wednesday,
    this.thursday,
    this.friday,
    this.saturday,
    this.sunday,
  });

  factory WeekPattern.fromJson(Map<String, dynamic> json) {
    return WeekPattern(
      monday: json['monday'] as bool?,
      tuesday: json['tuesday'] as bool?,
      wednesday: json['wednesday'] as bool?,
      thursday: json['thursday'] as bool?,
      friday: json['friday'] as bool?,
      saturday: json['saturday'] as bool?,
      sunday: json['sunday'] as bool?,
    );
  }
}
