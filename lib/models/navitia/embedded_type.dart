enum EmbeddedTypeEnum {
  line("line"),
  journeyPattern("journey_pattern"),
  vehicleJourney("vehicle_journey"),
  stopPoint("stop_point"),
  stopArea("stop_area"),
  network("network"),
  physicalMode("physical_mode"),
  commercialMode("commercial_mode"),
  connection("connection"),
  journeyPatternPoint("journey_pattern_point"),
  company("company"),
  route("route"),
  poi("poi"),
  contributor("contributor"),
  address("address"),
  poitype("poitype"),
  administrativeRegion("administrative_region"),
  calendar("calendar"),
  lineGroup("line_group"),
  impact("impact"),
  dataset("dataset"),
  trip("trip"),
  accessPoint("access_point");

  const EmbeddedTypeEnum(this.value);

  final String? value;
}
