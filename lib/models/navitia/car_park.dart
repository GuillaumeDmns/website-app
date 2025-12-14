class CarPark {
  final int? available;
  final int? totalPlaces;
  final int? occupiedPRM;
  final int? occupied;
  final int? availablePRM;
  final int? availableRidesharing;
  final int? occupiedRidesharing;
  final int? availableElectricVehicle;
  final int? occupiedElectricVehicle;
  final String? state;
  final bool? availability;

  CarPark(
      {this.availableRidesharing,
      this.occupiedRidesharing,
      this.availableElectricVehicle,
      this.occupiedElectricVehicle,
      this.state,
      this.availability,
      this.available,
      this.totalPlaces,
      this.occupiedPRM,
      this.occupied,
      this.availablePRM});

  factory CarPark.fromJson(Map<String, dynamic> json) {
    return CarPark(
      available: json['available'] as int?,
      totalPlaces: json['totalPlaces'] as int?,
      occupiedPRM: json['occupiedPRM'] as int?,
      occupied: json['occupied'] as int?,
      availablePRM: json['availablePRM'] as int?,
      availableRidesharing: json['availableRidesharing'] as int?,
      occupiedRidesharing: json['occupiedRidesharing'] as int?,
      availableElectricVehicle: json['availableElectricVehicle'] as int?,
      occupiedElectricVehicle: json['occupiedElectricVehicle'] as int?,
      state: json['state'] as String?,
      availability: json['availability'] as bool?,
    );
  }
}
