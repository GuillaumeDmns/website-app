class CallUnit {
  final String? expectedDepartureTime;
  final String? expectedArrivalTime;
  final String? aimedDepartureTime;
  final String? aimedArrivalTime;
  final String? departureStatus;
  final String? destinationDisplay;
  final String? arrivalPlatformName;
  final String? arrivalStatus;
  final bool? vehicleAtStop;
  final String? directionName;
  final String? destinationName;

  CallUnit({
    this.expectedDepartureTime,
    this.expectedArrivalTime,
    this.aimedDepartureTime,
    this.aimedArrivalTime,
    this.departureStatus,
    this.destinationDisplay,
    this.arrivalPlatformName,
    this.arrivalStatus,
    this.vehicleAtStop,
    this.directionName,
    this.destinationName,
  });

  factory CallUnit.fromJson(Map<String, dynamic> json) {
    return CallUnit(
      expectedDepartureTime: json['expectedDepartureTime'] as String?,
      expectedArrivalTime: json['expectedArrivalTime'] as String?,
      aimedDepartureTime: json['aimedDepartureTime'] as String?,
      aimedArrivalTime: json['aimedArrivalTime'] as String?,
      departureStatus: json['departureStatus'] as String?,
      destinationDisplay: json['destinationDisplay'] as String?,
      arrivalPlatformName: json['arrivalPlatformName'] as String?,
      arrivalStatus: json['arrivalStatus'] as String?,
      vehicleAtStop: json['vehicleAtStop'] as bool?,
      directionName: json['directionName'] as String?,
      destinationName: json['destinationName'] as String?,
    );
  }
}