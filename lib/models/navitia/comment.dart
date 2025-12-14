class Comment {
  final String? type;
  final String? value;

  Comment({this.type, this.value});

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      type: json['type'] as String?,
      value: json['value'] as String?,
    );
  }
}
