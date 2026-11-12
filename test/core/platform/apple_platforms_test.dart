import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/config.dart';
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/core/platform/platforms.dart';
import 'package:website_app/features/auth/google/google_auth.dart';
import 'package:website_app/features/home_widget/home_widget_sync.dart';
import 'package:website_app/l10n/l10n.dart';

/// iOS and macOS answer the same channel as Android (`AppBridge.swift`, `MainActivity.kt`)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('com.guillaumedamiens.live_notification/bridge');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    useLocale(const Locale('fr'));
    calls = [];
    messenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call);
      return call.method == 'takeStopRequest' ? true : null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(bridge, null);
  });

  test('the native side runs on Android, iOS and macOS only', () {
    for (final (platform, native, apple) in [
      (TargetPlatform.android, true, false),
      (TargetPlatform.iOS, true, true),
      (TargetPlatform.macOS, true, true),
      (TargetPlatform.linux, false, false),
      (TargetPlatform.windows, false, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(hasNativeBridge, native, reason: platform.name);
      expect(isApple, apple, reason: platform.name);
    }
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test("GO's live journey goes to the bridge on ${platform.name}", () async {
      debugDefaultTargetPlatformOverride = platform;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final live = container.read(liveJourneyProvider);

      await live.prepare();
      await live.update(const LiveJourneyUpdate(
        title: 'Marchez jusqu’à Châtelet',
        status: 'Quai 2',
        progress: 120,
        mode: 'walk',
        chip: '3 min',
        info: 'Arrivée 08:42',
        segments: [LiveJourneySegment(seconds: 300, color: '#9E9E9E'), LiveJourneySegment(seconds: 600, color: '#FFCD00')],
      ));
      await live.keepScreenOn(true);
      final stopped = await live.stopRequested();
      await live.stop();

      expect(calls.map((call) => call.method), [
        'requestNotificationPermission',
        'updateJourney',
        'keepScreenOn',
        'takeStopRequest',
        'keepScreenOn',
        'stopNotification',
      ]);
      expect(calls[1].arguments, {
        'title': 'Marchez jusqu’à Châtelet',
        'status': 'Quai 2',
        'progress': 120,
        'currentMode': 'walk',
        'chipText': '3 min',
        'longInfo': 'Arrivée 08:42',
        'segments': [
          {'length': 300, 'color': '#9E9E9E'},
          {'length': 600, 'color': '#FFCD00'},
        ],
      });
      expect(stopped, isTrue);
    });
  }

  test('a home screen widget on Android, iOS and macOS', () {
    for (final (platform, host) in [
      (TargetPlatform.android, WidgetHost.android),
      (TargetPlatform.iOS, WidgetHost.ios),
      (TargetPlatform.macOS, WidgetHost.macos),
      (TargetPlatform.linux, null),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(widgetHost, host, reason: platform.name);
      expect(homeWidgetSupported, host != null, reason: platform.name);
    }
  });

  test('macOS writes the widget through the bridge (home_widget has no macOS side)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await clearHomeWidget();

    expect(calls.single.method, 'saveWidget');
    expect(calls.single.arguments, {
      'stop_id': null,
      'stop_name': null,
      'departures_json': null,
      'last_updated': null,
      'updated_at': null,
      'departures_list': currentL10n.widgetOpenApp,
    });
  });

  test('the compass comes from iOS too, not from macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(deviceHeadings(), isNotNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(deviceHeadings(), isNull);
  });

  test('Google sign-in on iOS and macOS once their OAuth client is set', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(googleSignInAvailable, isTrue);
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(googleSignInAvailable, AppConfig.googleAppleClientId.isNotEmpty, reason: platform.name);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(googleSignInAvailable, isFalse);
  });

  test('Google sign-in on Linux and Windows goes through the browser, not the Google SDK', () {
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isLinuxOrWindows, isTrue, reason: platform.name);
      expect(googleSignInAvailable, isTrue, reason: platform.name);
      expect(googleSdkAvailable, isFalse, reason: platform.name);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isLinuxOrWindows, isFalse);
  });

  test("each environment has its own App Group (the dev and prod apps don't share a widget)", () {
    expect(AppConfig.iosAppGroup, AppConfig.isDev ? 'group.com.guillaumedamiens.app.dev' : 'group.com.guillaumedamiens.app');
  });
}
