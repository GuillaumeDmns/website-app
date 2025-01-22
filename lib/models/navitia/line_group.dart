import 'comment.dart';
import 'line.dart';

class LineGroup {
  final String? id;
  final String? name;
  final List<Line>? lines;
  final Line? mainLine;
  final List<Comment>? comments;

  LineGroup({this.id, this.name, this.lines, this.mainLine, this.comments});

  factory LineGroup.fromJson(Map<String, dynamic> json) {
    return LineGroup(
      id: json['id'] as String?,
      name: json['name'] as String?,
      lines: (json['lines'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((line) => Line.fromJson(line)))
          .toList(),
      mainLine: Line.fromJson(json['main_line']),
      comments: (json['comments'] as Map<String, dynamic>)
          .entries
          .expand((entry) =>
              (entry.value as List).map((comment) => Comment.fromJson(comment)))
          .toList(),
    );
  }
}
