import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/app/app.dart';
import 'package:website_app/core/api/api_providers.dart';
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/map/main_map.dart';
import 'package:website_app/core/storage/local_store.dart';
import 'package:website_app/features/auth/google/google_auth.dart';
import 'package:website_app/features/onboarding/onboarding.dart';
import 'package:website_app/l10n/l10n.dart';

import 'fake_backend.dart';
import 'memory_store.dart';
import 'test_container.dart';

/// Onboarding flag in memory: the real one is a device preference
class _TestOnboarding extends OnboardingController {
  _TestOnboarding(super.initial);

  @override
  Future<void> complete() async => state = true;
}

/// The account chooser of the tests: the user picks their Google account
Future<String?> _testGoogleAccount() async => 'test-google-id-token';

/// Châtelet
const userPosition = LatLng(48.8584, 2.3470);

/// The whole app (router, shell, map without tiles, every screen) on [backend], as a phone in French. Returns the
/// device storage.
Future<MemoryStore> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  MemoryStore? store,
  String? refreshToken,
  bool onboardingDone = true,
  LatLng? position = userPosition,
  Locale locale = const Locale('fr'),
  Size size = const Size(412, 915),
  Future<String?> Function()? googleAccountChooser = _testGoogleAccount,
  List<Override> overrides = const [],
}) async {
  FlutterSecureStorage.setMockInitialValues({refreshTokenKey: ?refreshToken});
  useLocale(locale);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);
  final deviceStore = store ?? MemoryStore();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioFactoryProvider.overrideWithValue(backend.dio),
      localStoreProvider.overrideWithValue(deviceStore),
      onboardingDoneProvider.overrideWith(() => _TestOnboarding(onboardingDone)),
      localeProvider.overrideWith(() => LocaleController(locale)),
      userLocationProvider.overrideWith((ref) => Stream.value(position)),
      // No compass: GO's map keeps the way's direction
      deviceHeadingProvider.overrideWith((ref) => const Stream.empty()),
      mapTilesEnabledProvider.overrideWithValue(false),
      googleAccountChooserProvider.overrideWithValue(googleAccountChooser),
      ...overrides,
    ],
    child: const MobilityApp(),
  ));
  await settle(tester);
  return deviceStore;
}

/// Lets the app load: requests, timers of the first frames, animations. The app keeps periodic timers (real time
/// refreshes, clock), so it never fully settles: pump for a while instead.
Future<void> settle(WidgetTester tester, [Duration duration = const Duration(seconds: 2)]) async {
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += const Duration(milliseconds: 100)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps [finder] (scrolled into view first) and lets the app react
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}

/// Unmounts the app so that its timers stop before the test ends
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Texts on screen, to understand a failing test
List<String?> visibleTexts(WidgetTester tester) => [
      for (final widget in tester.widgetList(find.byWidgetPredicate((widget) => widget is Text || widget is RichText)))
        if (widget is Text) widget.data ?? widget.textSpan?.toPlainText() else if (widget is RichText) widget.text.toPlainText(),
    ];
