import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/features/journey/widgets/journey_map.dart';

import '../../../support/samples.dart';

void main() {
  final start = DateTime.utc(2026, 10, 10, 8, 0);
  final trip = journey([
    walk(start, 300),
    transit(start.add(const Duration(minutes: 5)), 600),
  ]);

  Future<MapOverlay> overlayIn(WidgetTester tester, ThemeData theme) async {
    late MapOverlay overlay;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        overlay = journeyOverlay(context, trip);
        return const SizedBox.shrink();
      }),
    ));
    return overlay;
  }

  testWidgets('draws walks dark and dotted, in dark mode too: the map stays light', (tester) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      final walkPath = (await overlayIn(tester, theme)).paths.firstWhere((path) => path.dotted);

      expect(walkPath.color, walkPathColor);
      expect(walkPath.width, 5);
    }
  });

  testWidgets('draws rides in their line color', (tester) async {
    final ridePath = (await overlayIn(tester, ThemeData.light())).paths.firstWhere((path) => !path.dotted);

    expect(ridePath.color, const Color(0xFFFFCD00));
  });
}
