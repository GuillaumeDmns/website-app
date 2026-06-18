import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/permission_manager.dart';

class LocationUtils {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.guillaumedamiens.live_notification/bridge');

  static Future<bool> checkAndRequestLocationPermissions(
    BuildContext context, {
    String? title,
    String? description,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final result = await _nativeChannel.invokeMethod('requestLocationService');
          serviceEnabled = result == true;
        } on PlatformException {
          serviceEnabled = false;
        }
      } else if (context.mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Location services disabled'),
            content: const Text(
                'Please enable location services to use journey guidance.'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Open Settings'),
                onPressed: () {
                  Geolocator.openLocationSettings();
                  Navigator.of(context).pop(false);
                },
              ),
            ],
          ),
        );
        return false;
      }

      if (!serviceEnabled) return false;
    }

    if (!context.mounted) return false;
    return await PermissionManager().requestLocationPermission(
      context,
      title: title,
      description: description,
    );
  }

  static LocationSettings getPlatformLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        forceLocationManager: true,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Trajet en cours",
            notificationText: "Suivi de votre position pour vous guider.",
            setOngoing: true,
            enableWakeLock: true,
            color: Colors.green),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS  || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        showBackgroundLocationIndicator: false,
        activityType: ActivityType.otherNavigation,
        allowBackgroundLocationUpdates: true
      );
    } else if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        maximumAge: const Duration(minutes: 1),
      );
    } else {
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }
  }
}
