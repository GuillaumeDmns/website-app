import 'channel_types.dart';

class Channel {
  final String? contentType;
  final String? id;
  final String? name;
  final List<ChannelTypes>? types;

  Channel({
    this.contentType,
    this.id,
    this.name,
    this.types,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      contentType: json['content_type'] as String?,
      id: json['id'] as String?,
      name: json['name'] as String?,
      types: (json['types'] as List?)
          ?.map((e) => ChannelTypes.values.firstWhere(
            (enumItem) => enumItem.value == e
      ))
          .toList(),
    );
  }
}
