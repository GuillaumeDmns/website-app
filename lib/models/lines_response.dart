import 'line_dto.dart';

class LinesResponse {
  final Map<String, int> count;
  final List<LineDTO> lines;

  LinesResponse({required this.count, required this.lines});

  factory LinesResponse.fromJson(Map<String, dynamic> json) {
    final count = Map<String, int>.from(json['count'] as Map);
    final lines = (json['lines'] as Map<String, dynamic>)
        .entries
        .expand((entry) => (entry.value as List).map((line) => LineDTO.fromJson(line)))
        .toList();

    return LinesResponse(count: count, lines: lines);
  }
}