enum StopTimeEffect {
  delayed("DELAYED"),
  added("ADDED"),
  deleted("DELETED"),
  unchanged("UNCHANGED"),
  noAlighting("NO_ALIGHTING"),
  noBoarding("NO_BOARDING");

  const StopTimeEffect(this.value);

  final String? value;
}
