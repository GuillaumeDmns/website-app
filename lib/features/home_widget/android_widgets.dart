import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/routes.dart';
import '../../core/api/mobility_api.dart';
import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_request.dart';

/// Android's home screen widgets (`NextDepartures.kt`): each one shows the next departures of the stop its user chose
/// for it (`WidgetSetupScreen`), all its lines or the ones kept. What a widget reads is kept per widget id, as strings,
/// by home_widget: `w<id>_stop_id`, `w<id>_stop_name`, `w<id>_filter` (the ids of the lines kept, one per line of text;
/// none: every line), `w<id>_rows` ([androidWidgetRows]), `w<id>_message` (shown without rows) and
/// `w<id>_updated` (when, as shown in its header). The widget draws itself again as its departures leave, and says
/// how long until them within the hour when it can be drawn every minute (`NextDepartures.kt`); it is fetched again
/// every 15 min while the screen is on (`WidgetRefreshWorker.kt`) and when the app's home page shows.
const _qualifiedName = 'com.guillaumedamiens.app.NextDepartures';

/// Rows written at most (the widget shows the ones its height has room for) and departures per row (the widget drops
/// the ones that left since)
const androidWidgetMaxRows = 8;
const _timesPerRow = 5;

String _key(int widgetId, String name) => 'w${widgetId}_$name';

/// What the user chose for a widget
@immutable
class WidgetChoice {
  const WidgetChoice({required this.stopId, required this.stopName, this.lines});

  final String stopId;
  final String stopName;

  /// The ids of the lines shown, each in all its directions (a big station has dozens of destinations: choosing among
  /// them was a long list); null: all of them
  final Set<String>? lines;
}

/// The widget's rows: one per line and direction (of [lines] when given), the soonest first, at most
/// [androidWidgetMaxRows], one per line of text, each `line|background|text color|mode|destination|times`, `times`
/// being the next departures as `seconds since the epoch:state` joined by commas (`state`: `l` real time, `d` late,
/// `s` scheduled). The widget makes the time left or the clock time out of them when it is drawn.
@visibleForTesting
String androidWidgetRows(StopDepartures departures, {Set<String>? lines}) {
  String field(String? value) => (value ?? '').replaceAll('|', '/').replaceAll('\n', ' ');
  final groups = [
    for (final line in departures.lines)
      if (lines == null || lines.contains(line.line.id))
        if (line.departures.where((departure) => !departure.cancelled).toList() case final upcoming when upcoming.isNotEmpty)
          (line: line, upcoming: upcoming),
  ]..sort((a, b) => a.upcoming.first.time.compareTo(b.upcoming.first.time));
  return groups.take(androidWidgetMaxRows).map((group) {
    return [
      field(group.line.line.name),
      field(group.line.line.color),
      field(group.line.line.textColor),
      group.line.line.mode.name,
      field(group.line.destination),
      [
        for (final departure in group.upcoming.take(_timesPerRow))
          '${departure.time.millisecondsSinceEpoch ~/ 1000}:${departure.late ? 'd' : (departure.realtime ? 'l' : 's')}',
      ].join(','),
    ].join('|');
  }).map((row) => '$row\n').join();
}

/// The ids of the widgets on the home screen
Future<List<int>> _widgetIds() async => [
      for (final widget in await HomeWidget.getInstalledWidgets())
        if (widget.androidClassName == _qualifiedName) ?widget.androidWidgetId,
    ];

Future<void> _save(int widgetId, Map<String, String?> data) => Future.wait([
      for (final entry in data.entries) HomeWidget.saveWidgetData<String>(_key(widgetId, entry.key), entry.value),
    ]);

/// The departures were just fetched: the widget doesn't ask for them again as the screen comes on (`NextDepartures.kt`)
Future<void> _fetched(DateTime now) =>
    HomeWidget.saveWidgetData<String>('widgets_fetched_at', '${now.millisecondsSinceEpoch}');

Future<void> _redraw() => HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedName);

Future<WidgetChoice?> readWidgetChoice(int widgetId) async {
  final stopId = await HomeWidget.getWidgetData<String>(_key(widgetId, 'stop_id'));
  if (stopId == null) {
    return null;
  }
  final filter = await HomeWidget.getWidgetData<String>(_key(widgetId, 'filter'));
  return WidgetChoice(
    stopId: stopId,
    stopName: await HomeWidget.getWidgetData<String>(_key(widgetId, 'stop_name')) ?? '',
    lines: filter == null || filter.isEmpty ? null : filter.split('\n').toSet(),
  );
}

/// Keeps [choice] for the widget and shows [departures] (the stop's, just fetched) on it
Future<void> saveWidgetChoice(int widgetId, WidgetChoice choice, StopDepartures departures) async {
  try {
    await _save(widgetId, {
      'stop_id': choice.stopId,
      'stop_name': choice.stopName,
      'filter': choice.lines?.join('\n'),
      ...widgetContent(departures, DateTime.now(), lines: choice.lines),
    });
    await _fetched(DateTime.now());
    await _redraw();
  } catch (e) {
    debugPrint('Home widget choice failed: $e');
  }
}

/// What a widget shows of [departures]: its rows, else why there is none, and when they were fetched
@visibleForTesting
Map<String, String?> widgetContent(StopDepartures departures, DateTime now, {Set<String>? lines}) {
  final rows = androidWidgetRows(departures, lines: lines);
  return {
    'rows': rows.isEmpty ? null : rows,
    'message': rows.isEmpty ? currentL10n.widgetNoDeparture : null,
    'updated': formatClock(now),
  };
}

/// Fetches the departures of every widget's stop (one request per stop) and draws the widgets again. A stop that
/// can't be fetched keeps its departures, its widgets saying so.
Future<void> refreshAndroidWidgets(MobilityApi api) async {
  try {
    final choices = {
      for (final id in await _widgetIds())
        id: ?await readWidgetChoice(id),
    };
    if (choices.isEmpty) {
      return;
    }
    final fetched = <String, StopDepartures?>{};
    for (final stopId in {for (final choice in choices.values) choice.stopId}) {
      try {
        fetched[stopId] = await api.stopDepartures(stopId, limit: _timesPerRow);
      } catch (e) {
        debugPrint('Home widget refresh of $stopId failed: $e');
        fetched[stopId] = null;
      }
    }
    final now = DateTime.now();
    for (final MapEntry(key: id, value: choice) in choices.entries) {
      await _save(id, switch (fetched[choice.stopId]) {
        final departures? => widgetContent(departures, now, lines: choice.lines),
        null => {'updated': currentL10n.widgetFailedAt(formatClock(now))},
      });
    }
    if (fetched.values.any((departures) => departures != null)) {
      await _fetched(now);
    }
    await _redraw();
  } catch (e) {
    debugPrint('Home widget refresh failed: $e');
  }
}

/// Nothing could be fetched: the widgets say so, with the departures they had
Future<void> failAndroidWidgets() async {
  try {
    final failed = currentL10n.widgetFailedAt(formatClock(DateTime.now()));
    for (final id in await _widgetIds()) {
      if (await readWidgetChoice(id) != null) {
        await _save(id, {'updated': failed});
      }
    }
    await _redraw();
  } catch (e) {
    debugPrint('Home widget update failed: $e');
  }
}

/// What the app opens when the system starts it with [uri], as a location of the app; null for anything else:
/// - a home screen widget (`guillaumedamiens://stop?id=IDFM:71264`: its stop; `guillaumedamiens://widget?id=12`:
///   choosing its stop; the "Mes lignes" widget: `guillaumedamiens://line?id=C01371`, its line, and
///   `guillaumedamiens://traffic`, the traffic page);
/// - a place another app hands over (`geo:48.8606,2.3376?q=Louvre`, an address of the calendar or the contacts, "open
///   with" of a maps app): the journeys to it from here, or the search of its text when it has no position.
String? widgetLaunchLocation(Uri? uri) {
  if (uri == null) {
    return null;
  }
  if (uri.scheme == 'geo') {
    return _geoLocation(uri);
  }
  final id = uri.queryParameters['id'];
  return switch (uri.host) {
    'stop' when id != null && id.isNotEmpty => '/stops/${Uri.encodeComponent(id)}',
    'widget' when id != null && int.tryParse(id) != null => '/widget/$id',
    'line' when id != null && id.isNotEmpty => Routes.line(id),
    'traffic' => Routes.traffic,
    _ => null,
  };
}

/// Marks a link of the app opened from the launcher (a shortcut): see [launchLink]
const launchParameter = 'launch';

/// The link a launcher shortcut opens for [location], a location of the app (`/traffic`, `/journey?…`):
/// `guillaumedamiens://app/traffic?launch=1`. Android gives Flutter's router the path and the query of the link an
/// activity is started with, not its scheme nor its host: the location itself then, marked so that the router opens it
/// over the home page ([withoutLaunch]).
String launchLink(String location) {
  final uri = Uri.parse(location);
  return Uri(scheme: 'guillaumedamiens', host: 'app', path: uri.path, queryParameters: {...uri.queryParameters, launchParameter: '1'})
      .toString();
}

/// The location of the app a [launchLink] stands for, as the router gets it
String withoutLaunch(Uri uri) {
  final query = {...uri.queryParameters}..remove(launchParameter);
  return Uri(path: uri.path.isEmpty ? '/' : uri.path, queryParameters: query.isEmpty ? null : query).toString();
}

/// The journeys to [place] from here
String journeyTo(JourneyPlace place) => Routes.journey(JourneyRequest(from: const JourneyPlace.currentLocation(), to: place));

final _geoPoint = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)');
final _geoLabel = RegExp(r'\(([^)]*)\)\s*$');

/// `geo:lat,lon`, `geo:lat,lon?q=name`, `geo:0,0?q=lat,lon(name)` or `geo:0,0?q=an address` (RFC 5870 and Android's
/// own forms)
String? _geoLocation(Uri uri) {
  // geo: is not hierarchical: everything after the scheme, without Dart's own reading of it
  // (the router gives `geo:/48.86,2.33`)
  final text = uri.toString().substring('geo:'.length).replaceFirst(RegExp('^/+'), '');
  final mark = text.indexOf('?');
  final coordinates = (mark < 0 ? text : text.substring(0, mark)).split(';').first;
  String? query;
  for (final part in mark < 0 ? const <String>[] : text.substring(mark + 1).split('&')) {
    if (part.startsWith('q=')) {
      try {
        query = Uri.decodeQueryComponent(part.substring(2)).trim();
      } catch (_) {
        query = null;
      }
    }
  }
  (double, double)? point(String? value) {
    final match = value == null ? null : _geoPoint.firstMatch(value);
    final lat = double.tryParse(match?.group(1) ?? '');
    final lon = double.tryParse(match?.group(2) ?? '');
    // 0,0 stands for "no position, see the query"
    return lat == null || lon == null || (lat == 0 && lon == 0) || lat.abs() > 90 || lon.abs() > 180 ? null : (lat, lon);
  }

  final inQuery = point(query);
  final position = point(coordinates) ?? inQuery;
  if (position != null) {
    final label = query == null ? null : (_geoLabel.firstMatch(query)?.group(1)?.trim() ?? (inQuery == null ? query : null));
    return journeyTo(JourneyPlace.point(
      name: label == null || label.isEmpty ? currentL10n.pointOnMap : label,
      lat: position.$1,
      lon: position.$2,
    ));
  }
  return query == null || query.isEmpty ? null : Uri(path: Routes.search, queryParameters: {'q': query}).toString();
}
