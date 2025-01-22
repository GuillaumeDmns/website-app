import 'code.dart';
import 'link_schema.dart';

class Network {
  final String? id;
  final String? name;
  final List<LinkSchema>? links;
  final List<Code>? codes;

  Network({this.id, this.name, this.links, this.codes});

  factory Network.fromJson(Map<String, dynamic> json) {
    return Network(
      id: json['id'] as String?,
      name: json['name'] as String?,
      links: (json['links'] as List<dynamic>?)
          ?.map((code) => LinkSchema.fromJson(code))
          .toList(),
      codes: (json['codes'] as List<dynamic>?)
          ?.map((code) => Code.fromJson(code))
          .toList(),
    );
  }
}
