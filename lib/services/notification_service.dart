import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';

class NotificationService {
  static const String _channelId = 'journey_progress_channel';
  static const String _channelName = 'Journey Progress';
  static const String _channelDescription = 'Live journey progress';
  static const int _notificationId =
      75415; // Same value as https://github.com/Baseflow/flutter-geolocator/blob/756b8d8015f06ecfcc64b438f71cb3b362b5e350/geolocator_android/android/src/main/java/com/baseflow/geolocator/GeolocatorLocationService.java#L31

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
            defaultActionName: 'Open notification',
            defaultIcon: AssetsLinuxIcon('launch_background'));

    final DarwinInitializationSettings darwinInitializationSettings =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    // For macOS
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    // For macOS
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            linux: initializationSettingsLinux,
            iOS: darwinInitializationSettings,
            macOS: darwinInitializationSettings);

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  Future<void> showJourneyProgressNotification(Journey journey) async {
    if (journey.sections == null || journey.sections!.isEmpty) return;

    await _updateJourneyProgress(journey, journey.sections!.first, 0);
  }

  Future<void> updateJourneyProgressNotification(
      Journey journey,
      int currentSectionIndex,
      double traveledDistance,
      double totalDistance) async {
    if (journey.sections == null ||
        journey.sections!.length <= currentSectionIndex) return;

    final section = journey.sections![currentSectionIndex];
    await _updateJourneyProgress(
        journey,
        section,
        (traveledDistance.clamp(0, totalDistance) * 100 / totalDistance)
            .toInt());
  }

  Future<void> _updateJourneyProgress(
      Journey journey, Section currentSection, int traveledPercentage) async {
    final String contentText = _formatSectionText(currentSection);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      progress: traveledPercentage,
      maxProgress: 100,
      onlyAlertOnce: true,
    );

    final LinuxNotificationDetails linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
      category: LinuxNotificationCategory.device,
      resident: true,
      suppressSound: true,
      timeout: const LinuxNotificationTimeout.expiresNever(),
    );

    final appleDetails = DarwinNotificationDetails(threadIdentifier: _channelName);

    final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails, linux: linuxDetails, macOS: appleDetails, iOS: appleDetails);

    await _notificationsPlugin.show(
      _notificationId,
      'Journey to ${journey.sections?.last.to?.name ?? 'Destination'}',
      contentText,
      notificationDetails,
    );
  }

  Future<void> cancelJourneyNotification() async {
    await _notificationsPlugin.cancel(_notificationId);
  }

  String _formatSectionText(Section section) {
    final type = section.type ?? 'street_network';
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
