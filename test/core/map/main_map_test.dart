import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/map/main_map.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  const user = LatLng(48.8584, 2.3470);

  Future<ProviderContainer> pumpMap(WidgetTester tester) async {
    useLocale(const Locale('fr'));
    tester.view.physicalSize = const Size(400, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      mapTilesEnabledProvider.overrideWithValue(false),
      userLocationProvider.overrideWith((ref) => Stream.value(user)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('fr'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        // The panel hides the lower 300 px
        home: MainMap(padding: EdgeInsets.only(bottom: 300)),
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
}
