enum DisruptionStatus {
  past("past"),
  active("active"),
  future("future"),
  unknown("unknown");

  const DisruptionStatus(this.value);

  final String? value;
}
