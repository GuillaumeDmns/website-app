class LineDTO {
  final String? id;
  final String? name;
  final String? transportMode;
  final int? operatorId;
  final String? lineIdColor;
  final String? lineIdBackgroundColor;

  LineDTO({this.id, this.name, this.transportMode, this.operatorId, this.lineIdColor, this.lineIdBackgroundColor});

  factory LineDTO.fromJson(Map<String, dynamic> json) {
    return LineDTO(
      id: json['id'] as String?,
      name: json['name'] as String?,
      transportMode: json['transportMode'] as String?,
      operatorId: json['operatorId'] as int?,
      lineIdColor: json['lineIdColor'] as String?,
      lineIdBackgroundColor: json['lineIdBackgroundColor'] as String?,
    );
  }
}
