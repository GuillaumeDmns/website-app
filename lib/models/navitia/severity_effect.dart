enum SeverityEffect {
  noService("NO_SERVICE"),
  reducedService("REDUCED_SERVICE"),
  significantDelays("SIGNIFICANT_DELAYS"),
  detour("DETOUR"),
  additionalService("ADDITIONAL_SERVICE"),
  modifiedService("MODIFIED_SERVICE"),
  otherEffect("OTHER_EFFECT"),
  unknownEffect("UNKNOWN_EFFECT"),
  stopMoved("STOP_MOVED");

  const SeverityEffect(this.value);

  final String? value;
}
