import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationUtils {
  static Future<bool> checkAndRequestLocationPermissions(
      BuildContext context) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && context.mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Services de localisation désactivés'),
          content: const Text(
              'Veuillez activer les services de localisation pour le suivi.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Ouvrir les paramètres'),
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

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'La permission de localisation est requise pour suivre le trajet.')),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever && context.mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Permission de localisation refusée'),
          content: const Text(
              'La permission a été refusée de manière permanente. Veuillez l\'activer dans les paramètres de l\'application.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Ouvrir les paramètres'),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.of(context).pop(false);
              },
            ),
          ],
        ),
      );
      return false;
    }

    return true;
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
