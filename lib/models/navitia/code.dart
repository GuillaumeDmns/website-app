class Code {
  final String? type;
  final String? value;

  Code({this.type, this.value});

  factory Code.fromJson(Map<String, dynamic> json) {
    return Code(
      type: json['type'] as String?,
      value: json['value'] as String?,
    );
  }
}

