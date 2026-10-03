import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Icon of the current step: `Métro`, `RER`, `Train Transilien`, `TER`, `Tramway`, `Bus`, `transfer` or `walk`
  final String mode;

  /// Short status chip (`3 arrêts`, `2 min`)
  final String chip;
  final String info;
  final List<LiveJourneySegment> segments;
}

/// System side of GO mode: ongoing notification with the progress, alerts while the app is in the background, and
/// keeping the journey followed with the screen off. Android only for now (foreground service + Live Update);
/// nothing elsewhere, where GO works while the app is open.
abstract class LiveJourney {
  /// Asks what is needed before starting (notification permission)
  Future<void> prepare();

  Future<void> update(LiveJourneyUpdate update);

  Future<void> alert(String title, String body, {bool urgent = false});

  Future<void> stop();

  /// Whether alerts are given by the system (no need for an in-app sound)
  bool get systemAlerts;
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
  Future<void> stop() => _call('stopNotification');
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
}

final liveJourneyProvider = Provider<LiveJourney>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? _AndroidLiveJourney() : _NoLiveJourney(),
);
