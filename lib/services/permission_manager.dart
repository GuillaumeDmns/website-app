import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/permission_bottom_sheet.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  /// Handles location permission request with educational UI
  Future<bool> requestLocationPermission(
    BuildContext context, {
    String? title,
    String? description,
  }) async {
    PermissionStatus status = await Permission.location.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      return await _showPermanentlyDeniedDialog(
        context,
        'Localisation désactivée',
        'La permission de localisation est désactivée de manière permanente. Veuillez l\'activer dans les paramètres pour profiter du suivi en temps réel.',
      );
    }

    // Show educational UI before system prompt
    final bool? shouldRequest = await PermissionBottomSheet.show(
      context: context,
      icon: Icons.location_on_rounded,
      title: title ?? 'Suivi de votre trajet',
      description: description ??
          'Nous avons besoin de votre position pour vous guider tout au long de votre itinéraire et vous alerter en cas de changement.',
    );

    if (shouldRequest == true) {
      status = await Permission.location.request();
      
      if (status.isGranted) return true;
      
      if (status.isPermanentlyDenied && context.mounted) {
        return await _showPermanentlyDeniedDialog(
          context,
          'Localisation requise',
          'Pour vous guider, nous avons besoin de votre position. Veuillez l\'activer dans les paramètres.',
        );
      }
    }

    return status.isGranted;
  }

  /// Handles notification permission request with educational UI
  Future<bool> requestNotificationPermission(BuildContext context) async {
    PermissionStatus status = await Permission.notification.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // For notifications, we might not want to block the user with a hard dialog
      // but still offer a way to enable it.
      return false;
    }

    final bool? shouldRequest = await PermissionBottomSheet.show(
      context: context,
      icon: Icons.notifications_active_rounded,
      title: 'Alertes en direct',
      description: 'Recevez des notifications pour savoir quand descendre ou si votre trajet subit des perturbations.',
    );

    if (shouldRequest == true) {
      status = await Permission.notification.request();
    }

    return status.isGranted;
  }

  Future<bool> _showPermanentlyDeniedDialog(
    BuildContext context,
    String title,
    String content,
  ) async {
    if (!context.mounted) return false;
    
    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Paramètres'),
          ),
        ],
      ),
    );

    if (openSettings == true) {
      await openAppSettings();
    }
    
    return false;
  }
}
