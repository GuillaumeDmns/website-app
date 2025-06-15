class Path {
  final int? duration;

  final int? direction;

  final int? length;

  final String? name;

  Path({this.duration, this.direction, this.length, this.name});

  factory Path.fromJson(Map<String, dynamic> json) {
    return Path(
      duration: json['duration'] as int?,
      direction: json['direction'] as int?,
      length: json['length'] as int?,
      name: json['name'] as String?,
    );
  }
}
