import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart' as browser;
import 'platforms.dart';

/// Step of the journey in the progress bar of the notification
class LiveJourneySegment {
  const LiveJourneySegment({required this.seconds, required this.color});

  final int seconds;

  /// `#RRGGBB`
  final String color;
}

/// The line of the step in progress, as a badge in the notification
class LiveJourneyLine {
  const LiveJourneyLine({required this.name, required this.color, required this.textColor, required this.mode});

  final String name;

  /// `#RRGGBB`
  final String color;
  final String textColor;

  /// `metro`, `rer`, `bus`… (`TransportMode.name`): the badge's shape
  final String mode;
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
    this.line,
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

  /// Waiting for a ride or on board: its line
  final LiveJourneyLine? line;
}

/// System side of GO mode: ongoing notification with the progress and what to do now, and keeping the journey
/// followed with the screen off. Android: foreground service + Live Update. iOS: a Live Activity (lock screen and
/// Dynamic Island, `ios/NextDepartures/GoLiveActivity.swift`), the position kept in the background by the `location`
/// background mode. macOS: a quiet notification replaced in place. Web: screen kept on with the Wake Lock API. Nothing
/// elsewhere, where GO works while the app is open. No notification per alert: the app shows them.
abstract class LiveJourney {
  /// Asks what is needed before starting (notification permission)
  Future<void> prepare();

  Future<void> update(LiveJourneyUpdate update);

  /// What must be done now while the app isn't on screen (get off, a platform changed, a vehicle missed): a
  /// notification that rings and vibrates (Android), over the ongoing one, gone after a while
  Future<void> alert(String title, String? body);

  Future<void> stop();

  /// Keeps the screen on (or not) while GO mode is shown
  Future<void> keepScreenOn(bool on);

  /// "Terminer" in the notification (or the Live Activity) calls [stop] (the notification, its service or the Live
  /// Activity are already gone)
  void onStop(VoidCallback stop);

  /// "Terminer" was tapped while the app wasn't running: its session is over (asked once, at start-up)
  Future<bool> stopRequested();
}

/// Android, iOS and macOS: the same channel, answered by `MainActivity.kt` and `AppBridge.swift`
class _NativeLiveJourney implements LiveJourney {
  static const _channel = MethodChannel('com.guillaumedamiens.live_notification/bridge');

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
        if (update.line case final line?)
          'line': {'name': line.name, 'color': line.color, 'textColor': line.textColor, 'mode': line.mode},
      });

  @override
  Future<void> alert(String title, String? body) => _call('alertJourney', {'title': title, 'body': body});

  @override
  Future<void> stop() async {
    await _call('keepScreenOn', {'on': false});
    await _call('stopNotification');
  }

  @override
  Future<void> keepScreenOn(bool on) => _call('keepScreenOn', {'on': on});

  @override
  void onStop(VoidCallback stop) => _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') {
          stop();
        }
      });

  @override
  Future<bool> stopRequested() async {
    try {
      return await _channel.invokeMethod<bool>('takeStopRequest') ?? false;
    } catch (e) {
      debugPrint('LiveJourney.stopRequested failed: $e');
      return false;
    }
  }
}

class _NoLiveJourney implements LiveJourney {
  @override
  Future<void> alert(String title, String? body) async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}

  @override
  void onStop(VoidCallback stop) {}

  @override
  Future<bool> stopRequested() async => false;
}

/// Browser: the screen kept on only
class _WebLiveJourney implements LiveJourney {
  @override
  Future<void> alert(String title, String? body) async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> stop() => browser.keepScreenOn(false);

  @override
  Future<void> keepScreenOn(bool on) => browser.keepScreenOn(on);

  @override
  void onStop(VoidCallback stop) {}

  @override
  Future<bool> stopRequested() async => false;
}

final liveJourneyProvider = Provider<LiveJourney>(
  (ref) => kIsWeb
      ? _WebLiveJourney()
      : hasNativeBridge
          ? _NativeLiveJourney()
          : _NoLiveJourney(),
);
