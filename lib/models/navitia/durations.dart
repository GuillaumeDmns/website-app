class Durations {
  final int? taxi;

  final int? walking;

  final int? car;

  final int? ridesharing;

  final int? bike;

  final int? total;

  Durations(
      {this.taxi,
      this.walking,
      this.car,
      this.ridesharing,
      this.bike,
      this.total});

  factory Durations.fromJson(Map<String, dynamic> json) {
    return Durations(
      taxi: json['taxi'] as int?,
      walking: json['walking'] as int?,
      car: json['car'] as int?,
      ridesharing: json['ridesharing'] as int?,
      bike: json['bike'] as int?,
      total: json['total'] as int?,
    );
  }
}
