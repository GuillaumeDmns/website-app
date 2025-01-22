class FeedPublisher {
  final String? id;
  final String? name;
  final String? url;
  final String? license;

  FeedPublisher({this.id, this.name, this.url, this.license});

  factory FeedPublisher.fromJson(Map<String, dynamic> json) {
    return FeedPublisher(
      id: json['id'] as String?,
      name: json['name'] as String?,
      url: json['url'] as String?,
      license: json['license'] as String?,
    );
  }
}
