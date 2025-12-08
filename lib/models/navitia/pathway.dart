import 'access_point.dart';

class Pathway {
  final String? id;
  final String? name;
  final AccessPoint? accessPoint;
  final bool? isEntrance;
  final bool? isExit;
  final int? length;
  final int? traversalTime;
  final int? pathwayMode;
  final int? stairCount;
  final int? maxSlope;
  final int? minWidth;
  final String? signpostedAs;
  final String? reversedSignpostedAs;

  Pathway(
      {this.id,
      this.name,
      this.accessPoint,
      this.isEntrance,
      this.isExit,
      this.length,
      this.traversalTime,
      this.pathwayMode,
      this.stairCount,
      this.maxSlope,
      this.minWidth,
      this.signpostedAs,
      this.reversedSignpostedAs});

  factory Pathway.fromJson(Map<String, dynamic> json) {
    return Pathway(
      id: json['id'] as String?,
      name: json['name'] as String?,
      accessPoint: json['accessPoint'] != null
          ? AccessPoint.fromJson(json['accessPoint'])
          : null,
      isEntrance: json['isEntrance'] as bool?,
      isExit: json['isExit'] as bool?,
      length: json['length'] as int?,
      traversalTime: json['traversalTime'] as int?,
      pathwayMode: json['pathwayMode'] as int?,
      stairCount: json['stairCount'] as int?,
      maxSlope: json['maxSlope'] as int?,
      minWidth: json['minWidth'] as int?,
      signpostedAs: json['signpostedAs'] as String?,
      reversedSignpostedAs: json['reversedSignpostedAs'] as String?,
    );
  }
}
