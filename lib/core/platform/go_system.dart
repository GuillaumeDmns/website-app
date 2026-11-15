import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'app_shown.dart';

/// What the system holds back from GO, which the user can give it
enum GoSystemIssue {
  /// Only the approximate position is allowed (a few kilometers): GO can't follow the user, the schedule leads
  approximateLocation,

  /// No notification at all: nothing shows with the screen off, no alert rings
  notificationsOff,

  /// Notifications allowed, but not as a Live Update (Android 16: a setting per app): no chip, no lock screen progress
  liveUpdatesOff,
}

/// Asks the system what GO lacks, and opens the way to grant it. Android only: elsewhere nothing is checked.
class GoSystemChecks {
  const GoSystemChecks();

  static const _channel = MethodChannel('com.guillaumedamiens.live_notification/bridge');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The first thing to fix, the position before the notifications; null when nothing is missing or nothing is known
  Future<GoSystemIssue?> issue() async {
    if (!_android) {
      return null;
    }
    try {
      final permission = await Geolocator.checkPermission();
      final allowed = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
      if (allowed && await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
        return GoSystemIssue.approximateLocation;
      }
    } catch (e) {
      debugPrint('Location accuracy unknown: $e');
    }
    try {
      return switch (await _channel.invokeMethod<String>('notificationStatus')) {
        'off' => GoSystemIssue.notificationsOff,
        'liveOff' => GoSystemIssue.liveUpdatesOff,
        _ => null,
      };
    } catch (e) {
      debugPrint('Notification status unknown: $e');
      return null;
    }
  }

  /// The system's prompt or page where [issue] is fixed
  Future<void> fix(GoSystemIssue issue) async {
    try {
      switch (issue) {
        case GoSystemIssue.approximateLocation:
          // Android asks to change to the precise position; refused before, only its settings can
          await Geolocator.requestPermission();
          if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
            await Geolocator.openAppSettings();
          }
        case GoSystemIssue.notificationsOff:
          await _channel.invokeMethod<void>('openNotificationSettings', {'live': false});
        case GoSystemIssue.liveUpdatesOff:
          await _channel.invokeMethod<void>('openNotificationSettings', {'live': true});
      }
    } catch (e) {
      debugPrint('GO system issue not fixed: $e');
    }
  }
}

/// Replaced in the tests
final goSystemChecksProvider = Provider<GoSystemChecks>((ref) => const GoSystemChecks());

/// What GO lacks now, asked again each time the app comes back on screen (from the system's settings)
final goSystemIssueProvider = FutureProvider.autoDispose<GoSystemIssue?>((ref) {
  if (!ref.watch(appShownProvider)) {
    return null;
  }
  return ref.watch(goSystemChecksProvider).issue();
});
