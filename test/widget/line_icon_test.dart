import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/models/line_dto.dart';
import 'package:website_app/widgets/line_icon.dart';

void main() {
  group('LineIcon Widget Tests', () {
    testWidgets('Renders Metro LineIcon correctly', (WidgetTester tester) async {
      final line = LineDTO(
        id: 'line:IDFM:C01371',
        name: '1',
        transportMode: 'METRO',
        lineIdBackgroundColor: 'FFCD00',
        lineIdColor: '000000',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineIcon(line: line),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Renders RER LineIcon correctly', (WidgetTester tester) async {
      final line = LineDTO(
        id: 'line:IDFM:C01742',
        name: 'A',
        transportMode: 'RER',
        lineIdBackgroundColor: 'E2231A',
        lineIdColor: 'FFFFFF',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineIcon(line: line),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });
  });
}
