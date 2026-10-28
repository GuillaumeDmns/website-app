import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/map/main_map.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/map/map_panel.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  const user = LatLng(48.8584, 2.3470);
  // The panel hides the lower 300 px of the 800
  late MapPanel panel;

  Future<ProviderContainer> pumpMap(WidgetTester tester, {Stream<double> headings = const Stream.empty()}) async {
    panel = MapPanel(height: 300);
    addTearDown(panel.dispose);
    useLocale(const Locale('fr'));
    tester.view.physicalSize = const Size(400, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      mapTilesEnabledProvider.overrideWithValue(false),
      userLocationProvider.overrideWith((ref) => Stream.value(user)),
      deviceHeadingProvider.overrideWith((ref) => headings),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MainMap(panel: panel),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    return container;
  }

  /// Frames for the camera animations
  Future<void> animate(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  MapCamera camera(WidgetTester tester) => MapCamera.of(tester.element(find.byType(MarkerLayer)));

  testWidgets('follows the user with the way ahead up, low in the part of the map above the panel', (tester) async {
    final container = await pumpMap(tester);

    // Heading east
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: user, bearing: 90)));
    await animate(tester);

    final at = camera(tester).latLngToScreenOffset(user);
    final east = camera(tester).latLngToScreenOffset(const LatLng(48.8584, 2.3500));
    expect(east.dy, lessThan(at.dy - 50));
    expect((east.dx - at.dx).abs(), lessThan(2));
    // 72 % down the 500 px left above the panel
    expect(at.dy, closeTo(360, 4));
    expect(at.dx, closeTo(200, 4));
    expect(camera(tester).zoom, 18);

    // Moving the map by hand stops following, until "Recentrer"
    await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
    await animate(tester);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: user, bearing: 100)));
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(user).dy, isNot(closeTo(360, 4)));
    await tester.tap(find.byTooltip(currentL10n.recenter));
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(user).dy, closeTo(360, 4));
    expect(find.byTooltip(currentL10n.recenter), findsNothing);

    // Following over: north up again
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(fit: [user]));
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('turns with the device on foot, the way ahead up without compass', (tester) async {
    final headings = StreamController<double>.broadcast();
    addTearDown(headings.close);
    final container = await pumpMap(tester, headings: headings.stream);

    // No heading yet: the way's direction (east) is up
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: user, bearing: 90, compass: true)));
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(270, 0.5));

    // The phone in the hand turns south, then west: the map turns with it, the user still low on the screen
    headings.add(180);
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(180, 0.5));
    expect(camera(tester).latLngToScreenOffset(user).dy, closeTo(360, 4));
    headings.add(270);
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(90, 0.5));

    // A new position keeps the device's heading, not the way's
    const ahead = LatLng(48.8585, 2.3471);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: ahead, bearing: 90, compass: true)));
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(90, 0.5));
    expect(camera(tester).latLngToScreenOffset(ahead).dy, closeTo(360, 4));

    // A follow without compass ignores the device
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: ahead, bearing: 0)));
    await animate(tester);
    headings.add(45);
    await animate(tester);
    expect(camera(tester).rotation % 360, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('what is framed stays in the middle of the part above the panel while it moves, at once', (tester) async {
    final container = await pumpMap(tester);
    const stop = LatLng(48.8600, 2.3500);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(fit: [stop]));
    await animate(tester);
    // In the middle of the 500 px left above the panel
    expect(camera(tester).latLngToScreenOffset(stop).dy, closeTo(250, 2));
    final zoom = camera(tester).zoom;

    // Lowered: half of its move, the same frame, the zoom kept
    panel.update(live: 100, resting: 100);
    await tester.pump();
    await tester.pump();
    expect(camera(tester).latLngToScreenOffset(stop).dy, closeTo(350, 2));
    expect(camera(tester).zoom, zoom);
    // Raised past 70 % of the map: the map isn't looked at any more, the camera stops there
    panel.update(live: 700, resting: 700);
    await tester.pump();
    await tester.pump();
    expect(camera(tester).latLngToScreenOffset(stop).dy, closeTo((800 - 560) / 2, 2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('framing aims at where the panel goes to rest, the user followed at 72 % of what is left above it',
      (tester) async {
    final container = await pumpMap(tester);
    const stop = LatLng(48.8600, 2.3500);

    // The page changes: its sheet is on its way to 200 px
    panel.update(live: 300, resting: 200);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(fit: [stop]));
    panel.update(live: 200, resting: 200);
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(stop).dy, closeTo(300, 2));

    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: user, bearing: 0)));
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(user).dy, closeTo(600 * 0.72, 4));
    // The sheet dragged up: the user stays at 72 % of what is left
    panel.update(live: 400, resting: 400);
    await tester.pump();
    await tester.pump();
    expect(camera(tester).latLngToScreenOffset(user).dy, closeTo(400 * 0.72, 4));

    await tester.pumpWidget(const SizedBox());
  });
}
