class LinkSchema {
  final String? id;
  final String? title;
  final String? rel;
  final bool? templated;
  final bool? internal;
  final String? type;
  final String? href;
  final String? value;
  final String? category;
  final String? commentType;

  LinkSchema(
      {this.id,
      this.title,
      this.rel,
      this.templated,
      this.internal,
      this.type,
      this.href,
      this.value,
      this.category,
      this.commentType});

  factory LinkSchema.fromJson(Map<String, dynamic> json) {
    return LinkSchema(
      id: json['id'] as String?,
      title: json['title'] as String?,
      rel: json['rel'] as String?,
      templated: json['templated'] as bool?,
      internal: json['internal'] as bool?,
      type: json['type'] as String?,
      href: json['href'] as String?,
      value: json['value'] as String?,
      category: json['category'] as String?,
      commentType: json['commentType'] as String?,
    );
  }
}
