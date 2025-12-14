enum StatusEnum {
  unavailable("unavailable"),
  closed("closed"),
  open("open");

  const StatusEnum(this.value);

  final String? value;
}
