import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/api/mobility_api.dart';
import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';

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
          '${departure.time.millisecondsSinceEpoch ~/ 1000}:${departure.delayed ? 'd' : (departure.realtime ? 'l' : 's')}',
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

/// What the app opens from a widget (`guillaumedamiens://stop?id=IDFM:71264`: its stop; `guillaumedamiens://widget?
/// id=12`: choosing its stop), as a location of the app; null for anything else
String? widgetLaunchLocation(Uri? uri) {
  final id = uri?.queryParameters['id'];
  if (uri == null || id == null || id.isEmpty) {
    return null;
  }
  return switch (uri.host) {
    'stop' => '/stops/${Uri.encodeComponent(id)}',
    'widget' when int.tryParse(id) != null => '/widget/$id',
    _ => null,
  };
}
