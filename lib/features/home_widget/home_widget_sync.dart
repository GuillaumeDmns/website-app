import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/api/auth_api.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/api/mobility_api.dart';
import '../../app/routes.dart';
import '../../core/auth/token_store.dart';
import '../../core/config.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorites_controller.dart';
import '../stops/stop_screen.dart';
import 'android_widgets.dart';

/// Where the home screen widget lives: Android's `NextDepartures.kt`, the WidgetKit extension of iOS and macOS
/// (`ios/NextDepartures/`, also built for macOS). Android and iOS get their data through home_widget (iOS: the App
/// Group shared with the extension), macOS through the app's own bridge (`AppBridge.swift`: home_widget has no macOS
/// side).
enum WidgetHost { android, ios, macos }

WidgetHost? get widgetHost => kIsWeb
    ? null
    : switch (defaultTargetPlatform) {
        TargetPlatform.android => WidgetHost.android,
        TargetPlatform.iOS => WidgetHost.ios,
        TargetPlatform.macOS => WidgetHost.macos,
        _ => null,
      };

/// Home screen widget. Android: each widget shows the stop its user chose for it (`android_widgets.dart`,
/// `WidgetSetupScreen`). iOS and macOS: the next departures of the first favorite stop, else of the closest one, written
/// by the app when it shows them. The widget's refresh button (Android, iOS 17) fetches them in the background
/// ([homeWidgetBackgroundCallback]).
bool get homeWidgetSupported => widgetHost != null;

/// The widget's class: its package is the app's namespace, not the dev flavor's application id
const _qualifiedAndroidName = 'com.guillaumedamiens.app.NextDepartures';

/// The WidgetKit widget's kind (`NextDeparturesWidget.swift`)
const _appleName = 'NextDepartures';

const _bridge = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// Departures shown at most, as on the widget
const _rows = 4;

/// Writes [data] for the widget (a null value removes the key) and has it drawn again
Future<void> _write(Map<String, String?> data) async {
  switch (widgetHost) {
    case null:
      return;
    case WidgetHost.macos:
      await _bridge.invokeMethod<void>('saveWidget', data);
    case WidgetHost.android || WidgetHost.ios:
      await _useAppGroup();
      await Future.wait([for (final entry in data.entries) HomeWidget.saveWidgetData<String>(entry.key, entry.value)]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName, iOSName: _appleName);
  }
}

/// iOS: home_widget writes into the App Group shared with the extension (per isolate: the background one too)
Future<void> _useAppGroup() async {
  if (widgetHost == WidgetHost.ios) {
    await HomeWidget.setAppGroupId(AppConfig.iosAppGroup);
  }
}

Future<void> pushDeparturesToWidget(StopDepartures departures) async {
  if (!homeWidgetSupported) {
    return;
  }
  try {
    await _write(widgetData(departures, DateTime.now()));
  } catch (e) {
    debugPrint('Home widget update failed: $e');
  }
}

/// What the widget reads: the stop, its rows ([widgetRows]), the line under them in the app's language, and when they
/// were written (`updated_at`, UTC ISO 8601: iOS and macOS move to the following departure on their own as the clock
/// times pass)
@visibleForTesting
Map<String, String?> widgetData(StopDepartures departures, DateTime now) {
  final rows = widgetRows(departures);
  return {
    'stop_id': departures.stop.id,
    'stop_name': departures.stop.name,
    'departures_json': rows.isEmpty ? null : rows,
    'departures_list': rows.isEmpty ? currentL10n.widgetNoDeparture : null,
    'last_updated': currentL10n.widgetUpdated(formatClock(now)),
    'updated_at': now.toUtc().toIso8601String(),
  };
}

/// The widget's rows (design 2k1): one per line and direction, the soonest first, at most [_rows], one per line of
/// text, each `line|background|text color|time|destination|mode|state|next` (see `NextDepartures.kt`): clock times
/// rather than "3 min", the widget not being refreshed every minute; `state` is `live` (real time), `late` or empty;
/// `next` the following departure, or empty. Rows were joined with `||` before (five fields): the widget reads both.
@visibleForTesting
String widgetRows(StopDepartures departures) {
  String field(String? value) => (value ?? '').replaceAll('|', '/').replaceAll('\n', ' ');
  final groups = [
    for (final line in departures.lines)
      if (line.departures.where((departure) => !departure.cancelled).toList() case final upcoming when upcoming.isNotEmpty)
        (line: line, upcoming: upcoming),
  ]..sort((a, b) => a.upcoming.first.time.compareTo(b.upcoming.first.time));
  return groups.take(_rows).map((group) {
    final first = group.upcoming.first;
    final next = group.upcoming.length > 1 ? group.upcoming[1] : null;
    return [
      field(group.line.line.name),
      field(group.line.line.color),
      field(group.line.line.textColor),
      formatClock(first.time),
      field(group.line.destination),
      group.line.line.mode.name,
      first.delayed ? 'late' : (first.realtime ? 'live' : ''),
      if (next != null) formatClock(next.time) else '',
    ].join('|');
    // Every row ends with a new line, even a single one: the widget tells this format from the older one by it
  }).map((row) => '$row\n').join();
}

/// The widget's fetches in the background, always with the device's guest token, signed in or not: the account's
/// access token lives in the app's memory only, and renewing it here would rotate its refresh token at every widget
/// refresh, racing the app's own renewal (a refresh token used twice revokes all of the account's sessions). The
/// guest token is kept on the device for 30 days: no authentication call most of the time. Fetched again once when
/// missing, expiring or rejected.
@visibleForTesting
Future<Dio> widgetBackgroundDio(Dio dio, TokenStore tokens) async {
  final authApi = AuthApi(dio);
  Future<void> renew() async => tokens.saveGuest(await authApi.guest());
  if (!tokens.hasValidGuestToken) {
    await renew();
  }
  dio.options.headers['Authorization'] = 'Bearer ${tokens.guestToken}';
  dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 || request.extra['guestRenewed'] == true || request.path.contains('/auth/')) {
      return handler.next(error);
    }
    try {
      await tokens.clearGuest();
      await renew();
      request
        ..headers['Authorization'] = 'Bearer ${tokens.guestToken}'
        ..extra['guestRenewed'] = true;
      dio.options.headers['Authorization'] = 'Bearer ${tokens.guestToken}';
      handler.resolve(await dio.fetch<dynamic>(request));
    } catch (_) {
      handler.next(error);
    }
  }));
  return dio;
}

/// Refresh button of the widget (Android; iOS 17, through home_widget's `BackgroundIntent`) and its periodic refresh
/// (Android), run in a background isolate (the app may be closed): fetches the departures with the device's guest
/// token ([widgetBackgroundDio])
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'refreshdepartures') {
    return;
  }
  // Another isolate: the app's language and App Group are given again
  await loadLocale();
  await _useAppGroup();
  final android = widgetHost == WidgetHost.android;
  final stopId = android ? null : await HomeWidget.getWidgetData<String>('stop_id');
  if (!android && stopId == null) {
    await _write({'departures_list': currentL10n.widgetOpenApp});
    return;
  }
  final tokens = TokenStore();
  await tokens.load();
  try {
    final dio = await widgetBackgroundDio(
      Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10)))
        ..options.headers.addAll(AppConfig.clientHeaders),
      tokens,
    );
    if (android) {
      await refreshAndroidWidgets(MobilityApi(dio));
    } else {
      await pushDeparturesToWidget(await MobilityApi(dio).stopDepartures(stopId!, limit: 3));
    }
  } catch (e) {
    debugPrint('Home widget refresh failed: $e');
    if (android) {
      // No token, no network: the widgets say so, with the departures they had
      await failAndroidWidgets();
    } else {
      await _write({'last_updated': currentL10n.widgetUpdateFailed(formatClock(DateTime.now()))});
    }
  }
}

/// Another account: the widget forgets the stop (iOS, macOS: it came from the account's favorites; an Android widget
/// keeps the stop chosen for it, which says nothing of the account)
Future<void> clearHomeWidget() async {
  if (!homeWidgetSupported || widgetHost == WidgetHost.android) {
    return;
  }
  try {
    await _write({
      for (final key in ['stop_id', 'stop_name', 'departures_json', 'last_updated', 'updated_at']) key: null,
      'departures_list': currentL10n.widgetOpenApp,
    });
  } catch (e) {
    debugPrint('Home widget reset failed: $e');
  }
}

/// The widget's side of `MainActivity` (`WidgetBridge.kt`): what a tap on a widget opens, kept there until taken
const _widgetChannel = MethodChannel('com.guillaumedamiens.app/widget');

/// The location a widget's tap asked for and that nobody took yet, else null
Future<String?> _takeWidgetLaunch() async =>
    widgetLaunchLocation(Uri.tryParse(await _widgetChannel.invokeMethod<String>('takeLaunch') ?? ''));

/// What a home screen widget opened the app for (Android): its setup when the system places it, its stop or its
/// setup when tapped; null otherwise
Future<String?> initialWidgetLocation() async {
  if (widgetHost != WidgetHost.android) {
    return null;
  }
  try {
    if (int.tryParse(await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure() ?? '') case final id?) {
      return Routes.widgetSetup(id, configure: true);
    }
    return await _takeWidgetLaunch();
  } catch (e) {
    debugPrint('Home widget launch failed: $e');
    return null;
  }
}

/// A widget tapped while the app runs (Android): the location to open, taken from `MainActivity` when it says so,
/// and once at first in case the tap came before. A provider, so that the tests, without the native side, replace it.
final widgetClicksProvider = Provider<Stream<String>>((ref) {
  if (widgetHost != WidgetHost.android) {
    return const Stream.empty();
  }
  final clicks = StreamController<String>();
  Future<void> take() async {
    try {
      if (await _takeWidgetLaunch() case final location?) {
        clicks.add(location);
      }
    } catch (e) {
      debugPrint('Home widget launch failed: $e');
    }
  }

  _widgetChannel.setMethodCallHandler((call) async {
    if (call.method == 'launched') {
      await take();
    }
  });
  take();
  ref.onDispose(() {
    _widgetChannel.setMethodCallHandler(null);
    clicks.close();
  });
  return clicks.stream;
});

/// Registers the widget's refresh button (Android; iOS 17, where home_widget keeps the callback in the App Group)
Future<void> initHomeWidget() async {
  if (widgetHost == WidgetHost.android || widgetHost == WidgetHost.ios) {
    try {
      await _useAppGroup();
      await HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
    } catch (e) {
      debugPrint('Home widget registration failed: $e');
    }
  }
}

/// Invisible: keeps the widget on the departures the home page shows (first favorite stop, else [closest]); on Android,
/// fetches again the departures of the stops chosen for its widgets
class HomeWidgetSync extends ConsumerWidget {
  const HomeWidgetSync({super.key, required this.closest});

  final StopDepartures? closest;

  static String? _lastStop;
  static DateTime? _lastPush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!homeWidgetSupported) {
      return const SizedBox.shrink();
    }
    if (widgetHost == WidgetHost.android) {
      final now = DateTime.now();
      if (_lastPush == null || now.difference(_lastPush!) > const Duration(minutes: 1)) {
        _lastPush = now;
        final api = ref.read(mobilityApiProvider);
        Future.microtask(() => refreshAndroidWidgets(api));
      }
      return const SizedBox.shrink();
    }
    final favorite = (ref.watch(favoritesProvider).value ?? const <Favorite>[])
        .where((favorite) => favorite.kind == FavoriteKind.stop && favorite.stopAreaId != null)
        .firstOrNull;
    final departures = favorite == null ? closest : ref.watch(stopDeparturesProvider(favorite.stopAreaId!)).value;
    if (departures != null) {
      final now = DateTime.now();
      final stale = _lastPush == null || now.difference(_lastPush!) > const Duration(minutes: 1);
      if (departures.stop.id != _lastStop || stale) {
        _lastStop = departures.stop.id;
        _lastPush = now;
        Future.microtask(() => pushDeparturesToWidget(departures));
      }
    }
    return const SizedBox.shrink();
  }
}
