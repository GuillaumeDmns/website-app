import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/map/main_map.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/map/map_panel.dart';
import 'package:website_app/core/map/map_pins.dart';
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

  /// The circles on the map: the accuracy's around the user dot
  List<CircleMarker> circles(WidgetTester tester) => [
        for (final layer in tester.widgetList<CircleLayer>(find.byType(CircleLayer))) ...layer.circles,
      ];

  /// Where the user dot is on the screen
  Offset dot(WidgetTester tester) => tester.getCenter(find.byType(UserDot));

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

  testWidgets('walks are dots on the map itself, rides solid on a light edge', (tester) async {
    final container = await pumpMap(tester);
    const walk = [LatLng(48.8584, 2.3470), LatLng(48.8611, 2.3372)];
    const ride = [LatLng(48.8584, 2.3470), LatLng(48.8550, 2.3650)];
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(paths: [
      MapPath(points: walk, color: Color(0xFF3C4654), dotted: true),
      MapPath(points: ride, color: Color(0xFFFFCD00), width: 6),
    ]));
    await tester.pump();

    final polylines = tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
    expect(polylines.first.borderStrokeWidth, 0);
    expect(polylines.last.borderStrokeWidth, greaterThan(0));

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

  testWidgets("a circle of the fix's accuracy around the user dot, like Google Maps", (tester) async {
    final container = await pumpMap(tester);

    container.read(userAccuracyProvider.notifier).set(300);
    await tester.pump();
    final circle = circles(tester).single;
    expect(circle.point, user);
    expect(circle.radius, 300);
    expect(circle.useRadiusInMeter, isTrue);

    // Within the dot's halo: not drawn
    container.read(userAccuracyProvider.notifier).set(2);
    await tester.pump();
    expect(circles(tester), isEmpty);

    // GO's smoothed position, with its own fix's accuracy
    const walked = LatLng(48.8590, 2.3480);
    container.read(preciseUserPositionProvider.notifier).set(walked, accuracy: 400);
    await tester.pump();
    expect(circles(tester).single.point, walked);
    expect(circles(tester).single.radius, 400);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a vehicle followed from a line's page: the camera on it, the user dot and its circle on the user",
      (tester) async {
    final container = await pumpMap(tester);
    // 400 m east of the user
    const vehicle = LatLng(48.8584, 2.3525);
    container.read(userAccuracyProvider.notifier).set(300);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow.overhead(vehicle)));
    await animate(tester);

    expect(camera(tester).latLngToScreenOffset(vehicle), offsetMoreOrLessEquals(const Offset(200, 250), epsilon: 4));
    expect(dot(tester), offsetMoreOrLessEquals(camera(tester).latLngToScreenOffset(user), epsilon: 1));
    expect((circles(tester).single.point, circles(tester).single.radius), (user, 300));
    // The vehicle's way isn't the user's: no heading cone
    expect(tester.widget<UserDot>(find.byType(UserDot)).screenHeading, isNull);

    // GO going on meanwhile: the dot and its circle on its smoothed position, the camera still on the vehicle
    const walked = LatLng(48.8590, 2.3480);
    container.read(preciseUserPositionProvider.notifier).set(walked, accuracy: 60);
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(vehicle), offsetMoreOrLessEquals(const Offset(200, 250), epsilon: 4));
    expect(dot(tester), offsetMoreOrLessEquals(camera(tester).latLngToScreenOffset(walked), epsilon: 1));
    expect((circles(tester).single.point, circles(tester).single.radius), (walked, 60));

    // GO's own follow is the user's: the camera on the smoothed position, where the dot is, not on the last fix
    const fix = LatLng(48.8588, 2.3476);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow(position: fix, bearing: 0, user: true)));
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(walked), offsetMoreOrLessEquals(const Offset(200, 360), epsilon: 4));
    expect(dot(tester), offsetMoreOrLessEquals(camera(tester).latLngToScreenOffset(walked), epsilon: 1));
    expect(tester.widget<UserDot>(find.byType(UserDot)).screenHeading, isNotNull);

    await tester.pumpWidget(const SizedBox());
  });

  test('the circle of accuracy in pixels: wider at a closer zoom and further north, none within the halo', () {
    // MapLibre's 512 px tiles at zoom 18: 0.2986 m a pixel at the equator, half of it at 60°
    expect(AccuracyCircle.radiusFor(30, 0, 18, tileSize: 512), closeTo(100.5, 0.1));
    expect(AccuracyCircle.radiusFor(30, 60, 18, tileSize: 512), closeTo(201, 0.1));
    // flutter_map's 256 px tiles: the same zoom is twice as far
    expect(AccuracyCircle.radiusFor(30, 60, 18, tileSize: 256), closeTo(100.5, 0.1));
    expect(AccuracyCircle.radiusFor(3, 0, 18, tileSize: 512), isNull);
    expect(AccuracyCircle.radiusFor(null, 0, 18, tileSize: 512), isNull);
  });

  testWidgets('a pin turned from north turns with the map: a vehicle pointing the way it goes', (tester) async {
    final container = await pumpMap(tester);
    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(pins: [
      MapPin(point: user, color: Colors.black, rotation: 120, image: 'pointer', child: SizedBox.square(dimension: 20)),
    ]));
    await tester.pump();

    final turned = tester.widget<Transform>(
      find.ancestor(of: find.byType(PinView), matching: find.byType(Transform)).first,
    );
    // North up: its own rotation
    expect(turned.transform.getRotation().entry(1, 0), closeTo(math.sin(120 * math.pi / 180), 1e-6));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a station's ways in and out show close up only, under the other pins", (tester) async {
    final container = await pumpMap(tester);
    const pins = [
      MapPin(point: user, color: Colors.green, label: 'Châtelet'),
      MapPin(point: user, color: Colors.indigo, label: 'Sortie 3', closeUp: true, image: 'access-3', child: SizedBox.square(dimension: 20)),
    ];
    List<String?> shown() => [for (final pin in tester.widgetList<PinView>(find.byType(PinView))) pin.pin.label];

    container
        .read(mapOverlaysProvider.notifier)
        .set('/', const MapOverlay(pins: pins, follow: MapFollow(position: user, bearing: 0, zoom: 14, overhead: true)));
    await animate(tester);
    expect(camera(tester).zoom, lessThan(MapPin.closeUpZoom));
    expect(shown(), ['Châtelet']);

    container
        .read(mapOverlaysProvider.notifier)
        .set('/', const MapOverlay(pins: pins, follow: MapFollow(position: user, bearing: 0, zoom: 17, overhead: true)));
    await animate(tester);
    expect(camera(tester).zoom, 17);
    // Drawn first: under the station's own pin
    expect(shown(), ['Sortie 3', 'Châtelet']);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a vehicle followed from overhead: north up, in the middle of what is left above the panel', (tester) async {
    final container = await pumpMap(tester);

    container.read(mapOverlaysProvider.notifier).set('/', const MapOverlay(follow: MapFollow.overhead(user)));
    await animate(tester);
    expect(camera(tester).latLngToScreenOffset(user).dy, closeTo(250, 4));
    expect(camera(tester).rotation % 360, closeTo(0, 0.5));
    expect(camera(tester).zoom, 15);

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
