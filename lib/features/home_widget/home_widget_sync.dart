import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/api/auth_api.dart';
import '../../core/api/models.dart';
import '../../core/api/mobility_api.dart';
import '../../core/auth/token_store.dart';
import '../../core/config.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorites_controller.dart';
import '../stops/stop_screen.dart';

/// Android home screen widget (`NextDepartures.kt`): the next departures of the first favorite stop, else of the
/// closest one. The app writes them when it shows them; the widget's refresh button fetches them in the background
/// ([homeWidgetBackgroundCallback]).
bool get homeWidgetSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The widget's class: its package is the app's namespace, not the dev flavor's application id
const _qualifiedAndroidName = 'com.guillaumedamiens.app.NextDepartures';

/// Departures shown at most, as on the widget
const _rows = 4;

Future<void> pushDeparturesToWidget(StopDepartures departures) async {
  if (!homeWidgetSupported) {
    return;
  }
  final json = widgetRows(departures);
  try {
    await Future.wait([
      HomeWidget.saveWidgetData<String>('stop_id', departures.stop.id),
      HomeWidget.saveWidgetData<String>('stop_name', departures.stop.name),
      HomeWidget.saveWidgetData<String>('departures_json', json.isEmpty ? null : json),
      HomeWidget.saveWidgetData<String>('departures_list', json.isEmpty ? currentL10n.widgetNoDeparture : null),
      HomeWidget.saveWidgetData<String>('last_updated', currentL10n.widgetUpdated(formatClock(DateTime.now()))),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  } catch (e) {
    debugPrint('Home widget update failed: $e');
  }
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

/// Refresh button of the widget, run in a background isolate (the app may be closed): renews the account's access
/// token from the stored refresh token (or takes the device's guest token), then fetches the stop's departures
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'refreshdepartures') {
    return;
  }
  // Another isolate: the app's language is read again
  await loadLocale();
  final stopId = await HomeWidget.getWidgetData<String>('stop_id');
  if (stopId == null) {
    await HomeWidget.saveWidgetData<String>('departures_list', currentL10n.widgetOpenApp);
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
    return;
  }
  final tokens = TokenStore();
  await tokens.load();
  try {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10)));
    final authApi = AuthApi(dio);
    if (tokens.signedIn) {
      await tokens.save(await authApi.refresh(tokens.refreshToken!));
    } else if (!tokens.hasValidAccessToken) {
      await tokens.saveGuest(await authApi.guest());
    }
    dio.options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    await pushDeparturesToWidget(await MobilityApi(dio).stopDepartures(stopId, limit: 3));
  } catch (e) {
    debugPrint('Home widget refresh failed: $e');
    await HomeWidget.saveWidgetData<String>('last_updated', currentL10n.widgetUpdateFailed(formatClock(DateTime.now())));
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  }
}

/// Another account: the widget forgets the stop
Future<void> clearHomeWidget() async {
  if (!homeWidgetSupported) {
    return;
  }
  try {
    for (final key in ['stop_id', 'stop_name', 'departures_json', 'last_updated']) {
      await HomeWidget.saveWidgetData<String>(key, null);
    }
    await HomeWidget.saveWidgetData<String>('departures_list', currentL10n.widgetOpenApp);
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  } catch (e) {
    debugPrint('Home widget reset failed: $e');
  }
}

/// Registers the widget's refresh button (Android)
Future<void> initHomeWidget() async {
  if (homeWidgetSupported) {
    await HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
  }
}

/// Invisible: keeps the widget on the departures the home page shows (first favorite stop, else [closest])
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
