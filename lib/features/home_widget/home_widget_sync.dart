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
import '../favorites/favorites_controller.dart';
import '../stops/stop_screen.dart';

/// Android home screen widget (`NextDepartures.kt`): the next departures of the first favorite stop, else of the
/// closest one. The app writes them when it shows them; the widget's refresh button fetches them in the background
/// ([homeWidgetBackgroundCallback]).
bool get homeWidgetSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

const _androidName = 'NextDepartures';

/// Departures shown at most, as on the widget
const _rows = 4;

Future<void> pushDeparturesToWidget(StopDepartures departures) async {
  if (!homeWidgetSupported) {
    return;
  }
  final rows = [
    for (final line in departures.lines)
      for (final departure in line.departures.where((departure) => !departure.cancelled))
        (line: line.line, destination: line.destination, departure: departure),
  ]..sort((a, b) => a.departure.time.compareTo(b.departure.time));
  // Clock times rather than "3 min": the widget is not refreshed every minute
  final json = rows
      .take(_rows)
      .map((row) => '${row.line.name ?? ''}  ${formatClock(row.departure.time)}|${row.destination}'.replaceAll('||', ''))
      .join('||');
  try {
    await Future.wait([
      HomeWidget.saveWidgetData<String>('stop_id', departures.stop.id),
      HomeWidget.saveWidgetData<String>('stop_name', departures.stop.name),
      HomeWidget.saveWidgetData<String>('departures_json', rows.isEmpty ? null : json),
      HomeWidget.saveWidgetData<String>('departures_list', rows.isEmpty ? 'Aucun départ prochainement' : null),
      HomeWidget.saveWidgetData<String>('last_updated', formatClock(DateTime.now())),
    ]);
    await HomeWidget.updateWidget(androidName: _androidName);
  } catch (e) {
    debugPrint('Home widget update failed: $e');
  }
}

/// Refresh button of the widget, run in a background isolate (the app may be closed): renews the access token
/// from the stored refresh token, then fetches the stop's departures
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'refreshdepartures') {
    return;
  }
  final stopId = await HomeWidget.getWidgetData<String>('stop_id');
  final tokens = TokenStore();
  await tokens.load();
  final refreshToken = tokens.refreshToken;
  if (stopId == null || refreshToken == null) {
    await HomeWidget.saveWidgetData<String>('departures_list', 'Ouvrez l\'app pour choisir un arrêt');
    await HomeWidget.updateWidget(androidName: _androidName);
    return;
  }
  try {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10)));
    await tokens.save(await AuthApi(dio).refresh(refreshToken));
    dio.options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    await pushDeparturesToWidget(await MobilityApi(dio).stopDepartures(stopId, limit: 3));
  } catch (e) {
    debugPrint('Home widget refresh failed: $e');
    await HomeWidget.saveWidgetData<String>('last_updated', '${formatClock(DateTime.now())} (échec)');
    await HomeWidget.updateWidget(androidName: _androidName);
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
    await HomeWidget.saveWidgetData<String>('departures_list', 'Ouvrez l\'app pour choisir un arrêt');
    await HomeWidget.updateWidget(androidName: _androidName);
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
