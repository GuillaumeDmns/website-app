class Coord {
  final String? lat;
  final String? lon;

  Coord({this.lat, this.lon});

  factory Coord.fromJson(Map<String, dynamic> json) {
    return Coord(
      lat: json['lat'] as String?,
      lon: json['lon'] as String?,
    );
  }
}
