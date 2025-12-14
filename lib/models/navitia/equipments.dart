enum EquipmentsEnum {
  hasWheelchairAccessibility("has_wheelchair_accessibility"),
  hasBikeAccepted("has_bike_accepted"),
  hasAirConditioned("has_air_conditioned"),
  hasVisualAnnouncement("has_visual_announcement"),
  hasAudibleAnnouncement("has_audible_announcement"),
  hasAppropriateEscort("has_appropriate_escort"),
  hasAppropriateSignage("has_appropriate_signage"),
  hasSchoolVehicle("has_school_vehicle"),
  hasWheelchairBoarding("has_wheelchair_boarding"),
  hasSheltered("has_sheltered"),
  hasElevator("has_elevator"),
  hasEscalator("has_escalator"),
  hasBikeDepot("has_bike_depot");

  const EquipmentsEnum(this.value);

  final String? value;
}
