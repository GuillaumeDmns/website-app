import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart' as browser;

/// Step of the journey in the progress bar of the notification
class LiveJourneySegment {
  const LiveJourneySegment({required this.seconds, required this.color});

  final int seconds;

  /// `#RRGGBB`
  final String color;
}

class LiveJourneyUpdate {
  const LiveJourneyUpdate({
    required this.title,
    required this.status,
    required this.progress,
    required this.mode,
    required this.chip,
    required this.info,
    required this.segments,
  });

  final String title;
  final String status;

  /// Seconds done along the segments
  final int progress;

  /// Icon of the current step: `metro`, `train`, `tram`, `bus`, `transfer` or `walk`
  final String mode;

  /// Short status chip (`3 arrêts`, `2 min`)
  final String chip;
  final String info;
  final List<LiveJourneySegment> segments;
}

/// System side of GO mode: ongoing notification with the progress, alerts while the app is in the background, and
/// keeping the journey followed with the screen off. Android: foreground service + Live Update. Web: browser
/// notifications when the tab is hidden, screen kept on with the Wake Lock API. Nothing elsewhere, where GO works
/// while the app is open.
abstract class LiveJourney {
  /// Asks what is needed before starting (notification permission)
  Future<void> prepare();

  Future<void> update(LiveJourneyUpdate update);

  Future<void> alert(String title, String body, {bool urgent = false});

  Future<void> stop();

  /// Whether alerts are given by the system (no need for an in-app sound)
  bool get systemAlerts;

  /// Keeps the screen on (or not) while GO mode is shown
  Future<void> keepScreenOn(bool on);
}

class _AndroidLiveJourney implements LiveJourney {
  static const _channel = MethodChannel('com.guillaumedamiens.live_notification/bridge');

  @override
  bool get systemAlerts => true;

  Future<void> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      debugPrint('LiveJourney.$method failed: $e');
    }
  }

  @override
  Future<void> prepare() => _call('requestNotificationPermission');

  @override
  Future<void> update(LiveJourneyUpdate update) => _call('updateJourney', {
        'title': update.title,
        'status': update.status,
        'progress': update.progress,
        'currentMode': update.mode,
        'chipText': update.chip,
        'longInfo': update.info,
        'segments': [
          for (final segment in update.segments) {'length': segment.seconds, 'color': segment.color},
        ],
      });

  @override
  Future<void> alert(String title, String body, {bool urgent = false}) =>
      _call('alert', {'title': title, 'body': body, 'urgent': urgent});

  @override
  Future<void> stop() async {
    await _call('keepScreenOn', {'on': false});
    await _call('stopNotification');
  }

  @override
  Future<void> keepScreenOn(bool on) => _call('keepScreenOn', {'on': on});
}

class _NoLiveJourney implements LiveJourney {
  @override
  bool get systemAlerts => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> alert(String title, String body, {bool urgent = false}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}
}

/// Browser: notifications only when the tab is hidden (the app shows its own banner otherwise)
class _WebLiveJourney implements LiveJourney {
  @override
  bool get systemAlerts => false;

  @override
  Future<void> prepare() => browser.requestNotifications();

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> alert(String title, String body, {bool urgent = false}) async {
    if (browser.pageHidden) {
      browser.notify(title, body);
    }
  }

  @override
  Future<void> stop() => browser.keepScreenOn(false);

  @override
  Future<void> keepScreenOn(bool on) => browser.keepScreenOn(on);
}

final liveJourneyProvider = Provider<LiveJourney>(
  (ref) => kIsWeb
      ? _WebLiveJourney()
      : defaultTargetPlatform == TargetPlatform.android
          ? _AndroidLiveJourney()
          : _NoLiveJourney(),
);
