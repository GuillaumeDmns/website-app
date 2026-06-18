import 'channel.dart';

class Message {
  final String? text;
  final Channel? channel;

  Message({
    this.text,
    this.channel,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      text: json['text'] as String?,
      channel:
          json['channel'] != null ? Channel.fromJson(json['channel']) : null,
    );
  }
}
