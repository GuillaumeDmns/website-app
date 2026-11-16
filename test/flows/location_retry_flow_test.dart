import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The app leaves the screen and comes back, as behind a window of the system or another app
Future<void> _leaveAndComeBack(WidgetTester tester) async {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await settle(tester);
}

/// Looking for the position again when the app comes back on screen
void main() {
  testWidgets('back on screen without a position, the app looks for it again', (tester) async {
    var searches = 0;
    // Location off, or its permission refused
    await pumpApp(tester, standardBackend(), positions: () {
      searches++;
      return Stream<LatLng?>.value(null);
    });
    expect(searches, 1);

    // The user turns location on in the system settings
    await _leaveAndComeBack(tester);

    expect(searches, 2);

    await closeApp(tester);
  });

  testWidgets("a window of the system closed while the position is looked for doesn't ask again", (tester) async {
    var searches = 0;
    final answer = StreamController<LatLng?>();
    addTearDown(answer.close);
    // The device waits for the user's answer (the permission, Google's location accuracy)
    await pumpApp(tester, standardBackend(), positions: () {
      searches++;
      return searches == 1 ? answer.stream : Stream<LatLng?>.value(null);
    });

    // Refused: the window closes, then the position is given up
    await _leaveAndComeBack(tester);
    answer.add(null);
    await settle(tester);

    expect(searches, 1);

    // Left again, for the system settings this time
    await _leaveAndComeBack(tester);

    expect(searches, 2);

    await closeApp(tester);
  });
}
