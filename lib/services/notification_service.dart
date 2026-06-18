import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';

class NotificationService {
  static const String _channelId = 'journey_progress_channel';
  static const String _channelName = 'Journey Progress';
  static const String _channelDescription = 'Live journey progress';

  static const int _notificationId =
      75415; // Same value as https://github.com/Baseflow/flutter-geolocator/blob/756b8d8015f06ecfcc64b438f71cb3b362b5e350/geolocator_android/android/src/main/java/com/baseflow/geolocator/GeolocatorLocationService.java#L31

  static const MethodChannel _nativeChannel =
  MethodChannel('com.guillaumedamiens.live_notification/bridge');

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final NotificationService _notificationService =
      NotificationService._internal();

  factory NotificationService() => _notificationService;

  NotificationService._internal();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
            defaultActionName: 'Open App',
            defaultIcon: ThemeLinuxIcon('network-transmit'));

    const DarwinInitializationSettings darwinInitializationSettings =
        DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final WindowsInitializationSettings windowsInitializationSettings =
        WindowsInitializationSettings(
            appName: 'Guillaume',
            appUserModelId: 'Com.GuillaumeDamiens.App',
            guid: '9772cf58-6762-4621-8ae2-0c03aba9dfa1');

    final InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            linux: initializationSettingsLinux,
            iOS: darwinInitializationSettings,
            macOS: darwinInitializationSettings,
            windows: windowsInitializationSettings);

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  Future<void> requestWebNotificationPermission() async {
    if (kIsWeb) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showJourneyProgressNotification(Journey journey) async {
    if (journey.sections == null || journey.sections!.isEmpty) return;
    await updateJourneyProgressNotification(journey, 0, 0, 0);
  }

  Future<void> updateJourneyProgressNotification(
      Journey journey,
      int currentSectionIndex,
      double traveledDistance,
      double totalJourneyDistance) async {
      
    final sections = journey.sections!;
    if (sections.length <= currentSectionIndex) return;

    Section? currentSection = sections[currentSectionIndex];
    String currentMode = _getSectionMode(currentSection);

    int remainingSeconds = 0;
    for (int i = currentSectionIndex; i < sections.length; i++) {
      remainingSeconds += sections[i].duration ?? 0;
    }
    String remainingTimeStr = "${(remainingSeconds / 60).ceil()} min";

    String chipText = _generateShortChipText(currentSection, remainingTimeStr);
    String longInfo = _generateLongInfoText(currentSection, remainingTimeStr);
    String destName = sections.lastWhere((s) => s.to?.name != null, orElse: () => sections.last).to?.name ?? 'Destination';
    String title = "Trip to $destName";
    String status = "Remaining: $remainingTimeStr • ${_buildStatusText(traveledDistance)}";
    int remainingMinutes = (remainingSeconds / 60).ceil();

    String subtitle = _generateSubtitle(currentSection);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _updateAndroidNativeNotification(
        journey: journey,
        sections: sections,
        currentSectionIndex: currentSectionIndex,
        currentSection: currentSection,
        currentMode: currentMode,
        distanceTraveledMeters: traveledDistance,
        remainingTimeStr: remainingTimeStr,
        chipText: chipText,
        longInfo: longInfo,
        title: title,
        status: status,
      );
    } else {
      await _updateCrossPlatformNotification(
        title: title,
        subtitle: subtitle,
        contentText: "$chipText • $status",
        traveledPercentage: totalJourneyDistance > 0 ? ((traveledDistance / totalJourneyDistance) * 100).toInt() : 0,
        remainingMinutes: remainingMinutes,
        chipText: chipText,
        destName: destName,
        remainingTimeStr: remainingTimeStr,
      );
    }
  }

  Future<void> cancelJourneyNotification() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeChannel.invokeMethod('stopNotification');
      } catch (e) {
        debugPrint(e.toString());
      }
    }
    await _notificationsPlugin.cancel(id: _notificationId);
  }

  Future<void> _updateAndroidNativeNotification({
    required Journey journey,
    required List<Section> sections,
    required int currentSectionIndex,
    required Section currentSection,
    required String currentMode,
    required double distanceTraveledMeters,
    required String remainingTimeStr,
    required String chipText,
    required String longInfo,
    required String title,
    required String status,
  }) async {
    final segmentsPayload = sections
        .where((s) =>
            !["crow_fly", "waiting", "transfer", "street_network"].contains(s.type) &&
            s.mode != "walking" &&
            (s.geojson?.properties?[0].length ?? 0) > 0)
        .map((section) {
      return {
        'length': section.geojson?.properties?[0].length ?? 0,
        'color': _getHexColorForSection(section),
        'type': section.type ?? 'unknown',
      };
    }).toList();

    String mainColor = "#050A11";
    for (int i = currentSectionIndex; i < sections.length; i++) {
      Section s = sections[i];
      String mode = _getSectionMode(s);
      if (mode != "default" && mode != "walking" && mode != "transfer" && s.type != "waiting" && s.type != "crow_fly") {
        String secColor = _getHexColorForSection(s);
        if (secColor != "#D3D3D3" && secColor != "#A0A0A0") {
          mainColor = secColor;
          break;
        }
      }
    }

    try {
      await _nativeChannel.invokeMethod('updateJourney', {
        'title': title,
        'status': status,
        'progress': distanceTraveledMeters.toInt(),
        'currentMode': currentMode,
        'mainColor': mainColor,
        'remainingTime': remainingTimeStr,
        'chipText': chipText,
        'longInfo': longInfo,
        'segments': segmentsPayload,
      });
    } on PlatformException catch (e) {
      debugPrint("Bridge Error: ${e.message}");
    }
  }

  Future<void> _updateCrossPlatformNotification({
    required String title,
    required String subtitle,
    required String contentText,
    required int traveledPercentage,
    required int remainingMinutes,
    required String chipText,
    required String destName,
    required String remainingTimeStr,
  }) async {
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

    final DarwinNotificationDetails appleDetails = DarwinNotificationDetails(
      subtitle: subtitle,
      threadIdentifier: _channelName,
      badgeNumber: remainingMinutes > 0 ? remainingMinutes : null,
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final windowsDetails = WindowsNotificationDetails(
      progressBars: <WindowsProgressBar>[
        WindowsProgressBar(
          id: _channelName,
          title: chipText,
          status: remainingTimeStr,
          value: traveledPercentage / 100,
        )
      ],
      actions: <WindowsAction>[
        WindowsAction(
          content: 'Open App',
          arguments: 'open_app',
          activationType: WindowsActivationType.foreground,
          activationBehavior: WindowsNotificationBehavior.dismiss,
        ),
      ],
      scenario: WindowsNotificationScenario.reminder,
    );

    final LinuxNotificationDetails linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
      category: LinuxNotificationCategory.device,
      resident: true,
      suppressSound: true,
      timeout: const LinuxNotificationTimeout.expiresNever(),
      actions: <LinuxNotificationAction>[
        const LinuxNotificationAction(
          key: 'open',
          label: 'Open App',
        ),
      ],
    );

    const WebNotificationDetails webDetails = WebNotificationDetails(
      requireInteraction: true,
      isSilent: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
      macOS: appleDetails,
      iOS: appleDetails,
      windows: windowsDetails,
      web: webDetails,
    );

    await _notificationsPlugin.show(
      id: _notificationId,
      title: title,
      body: contentText,
      notificationDetails: notificationDetails,
    );
  }

  String _generateSubtitle(Section? section) {
    if (section == null) return '';
    if (section.mode == 'walking' || section.type == 'street_network') {
      final dest = section.to?.name;
      return dest != null ? 'Walk to $dest' : 'Walking';
    }
    if (section.type == 'transfer') return 'Transfer';
    if (section.displayInformations != null) {
      final mode = section.displayInformations!.commercialMode ?? '';
      final code = section.displayInformations!.code ?? '';
      final direction = section.displayInformations?.direction ?? '';
      if (direction.isNotEmpty) {
        return '$mode $code → $direction';
      }
      return '$mode $code';
    }
    return '';
  }

  String _generateShortChipText(Section section, String timeStr) {
    String currentMode = _getSectionMode(section);
    String code = section.displayInformations?.code ?? "";

    switch (currentMode) {
      case 'RER':
        return "RER $code";
      case 'Train Transilien':
      case 'Train':
        return "Train $code";
      case 'TER':
        return "TER";
      case 'Métro':
      case 'Metro':
        return "Metro $code";
      case 'Tramway':
      case 'Tram':
        return "Tram $code";
      case 'Bus':
      case 'public_transport':
      case 'vehicle':
        return "Bus $code";
      case 'transfer':
        return "Transfer";
      case 'crow_fly':
        return "Crowfly";
      case 'waiting':
        return "Wait";
      case 'walking':
      case 'street_network':
        return 'Walk';
      default:
        return timeStr.replaceAll(" min", "'");
    }
  }

  String _generateLongInfoText(Section section, String timeStr) {
    String modePart = "";
    if (section.mode == "walking" || section.type == "street_network") {
      modePart = "Walk";
    } else if (section.displayInformations != null) {
      modePart =
          "${section.displayInformations!.commercialMode} ${section.displayInformations!.code}";
    } else if (section.type == "transfer") {
      modePart = "Transfer";
    }

    if (modePart.isNotEmpty) {
      return "$modePart • $timeStr";
    }
    return timeStr;
  }

  String _getHexColorForSection(Section section) {
    if (section.displayInformations?.color != null && section.displayInformations!.color!.isNotEmpty) {
      return "#${section.displayInformations!.color}";
    }
    if (section.type == "street_network" || section.type == "transfer" || section.mode == "walking") {
      return "#A0A0A0"; 
    }
    return "#D3D3D3";
  }

  String _buildStatusText(double distTraveled) {
    String distStr = (distTraveled > 1000)
        ? "${(distTraveled / 1000).toStringAsFixed(1)} km"
        : "${distTraveled.toInt()} m";
    return "Traveled: $distStr";
  }

  String _getSectionMode(Section section) {
    return section.displayInformations?.commercialMode ??
        section.mode ??
        section.type ??
        "default";
  }

  static void onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {}

  static void onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {}
}
