import 'call_unit.dart';

class UnitIDFMDTO {
  final List<CallUnit> nextPassages;
  final List<String> nextPassageDestinations;

  UnitIDFMDTO({
    required this.nextPassages,
    required this.nextPassageDestinations,
  });

  factory UnitIDFMDTO.fromJson(Map<String, dynamic> json) {
    return UnitIDFMDTO(
      nextPassages: (json['nextPassages'] as List<dynamic>?)
              ?.map((e) => CallUnit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextPassageDestinations:
          (json['nextPassageDestinations'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
    );
  }
}
