import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showJourneyProgressNotification(Journey journey) async {
    if (journey.sections == null || journey.sections!.isEmpty) return;
    await _updateJourneyProgress(journey, journey.sections!.first, 0);
  }

  Future<void> updateJourneyProgressNotification(Journey journey, int currentSectionIndex) async {
    if (journey.sections == null || journey.sections!.length <= currentSectionIndex) return;

    final section = journey.sections![currentSectionIndex];
    await _updateJourneyProgress(journey, section, currentSectionIndex);
  }

  Future<void> _updateJourneyProgress(Journey journey, Section currentSection, int currentStep) async {
    final int totalSteps = journey.sections?.length ?? 1;
    final String contentText = _formatSectionText(currentSection);

    final int notificationId = journey.hashCode;

    if (Platform.isAndroid) {
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'journey_progress_channel',
        'Journey Progress',
        channelDescription: 'Shows live journey progress',
        importance: Importance.low,
        priority: Priority.defaultPriority,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        maxProgress: totalSteps,
        progress: currentStep + 1,
        onlyAlertOnce: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        notificationId,
        'Journey to ${journey.sections?.last.to?.name ?? 'Destination'}',
        contentText,
        notificationDetails,
      );

    }
  }

  Future<void> cancelJourneyNotification(Journey journey) async {
    await _notificationsPlugin.cancel(journey.hashCode);
  }

  String _formatSectionText(Section section) {
    final type = section.type ?? 'street_network' ;
    if (type == 'public_transport') {
      final mode = section.displayInformations?.commercialMode ?? '';
      final line = section.displayInformations?.label ?? '';
      final direction = section.displayInformations?.direction ?? '';
      return '$mode $line towards $direction';
    } else if (type == 'street_network') {
      final mode = section.mode == 'walking' ? 'Walk' : 'Ride';
      return '$mode to ${section.to?.name ?? 'next stop'}';
    }
    return 'Proceed to next step';
  }

  static void onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {}

  static void onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {}
}