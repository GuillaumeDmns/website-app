class CallUnit {
  final String? expectedDepartureTime;
  final String? destinationName;
  final String? arrivalPlatformName;
  final String? departureStatus;

  CallUnit({
    this.expectedDepartureTime,
    this.destinationName,
    this.arrivalPlatformName,
    this.departureStatus,
  });

  factory CallUnit.fromJson(Map<String, dynamic> json) {
    return CallUnit(
      expectedDepartureTime: json['expectedDepartureTime'] as String?,
      destinationName: json['destinationName'] as String?,
      arrivalPlatformName: json['arrivalPlatformName'] as String?,
      departureStatus: json['departureStatus'] as String?,
    );
  }
}