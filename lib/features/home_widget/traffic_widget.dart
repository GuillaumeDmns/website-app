import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/api/mobility_api.dart';
import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';

/// Android's "Mes lignes" widget (`LinesTraffic.kt`): the traffic of the user's favorite lines, the worst first. No
/// setup: every such widget shows the same lines. What it reads is kept by home_widget, as strings:
/// - `traffic_lines`: the favorite lines ([trafficWidgetLines]), written by the app whenever they change, so that the
///   widget's own refresh in the background knows them without the account;
/// - `traffic_rows` ([trafficWidgetRows]), `traffic_message` (shown without rows), `traffic_updated` (when, as shown in
///   its header) and `traffic_fetched_at` (ms since the epoch: the widget asks again once it is 10 min old).
/// The traffic is `/api/v2/traffic`, the backend's snapshot of the whole network: no PRIM quota spent per call.
const trafficWidgetName = 'com.guillaumedamiens.app.LinesTraffic';

/// Rows written at most (the widget shows the ones its height has room for)
const trafficWidgetMaxRows = 8;

String _field(String? value) => (value ?? '').replaceAll('|', '/').replaceAll('\n', ' ');

/// The favorite lines, in their order, one per line of text: `id|name|background|text color|mode`
@visibleForTesting
String trafficWidgetLines(List<Favorite> favorites) => [
      for (final favorite in favorites)
        if (favorite.line case final line? when favorite.kind == FavoriteKind.line && line.id.isNotEmpty)
          '${[_field(line.id), _field(line.name), _field(line.color), _field(line.textColor), line.mode.name].join('|')}\n',
    ].join();

/// The lines [trafficWidgetLines] wrote
@visibleForTesting
List<LineSummary> readTrafficWidgetLines(String? text) => [
      for (final row in (text ?? '').split('\n'))
        if (row.split('|') case [final id, final name, final color, final textColor, final mode, ...] when id.isNotEmpty)
          LineSummary(
            id: id,
            name: name.isEmpty ? null : name,
            color: color.isEmpty ? null : color,
            textColor: textColor.isEmpty ? null : textColor,
            mode: TransportMode.values.asNameMap()[mode] ?? TransportMode.bus,
          ),
    ];

/// The widget's rows: one per line of [lines], the interrupted ones first, then the disrupted ones, then the others
/// in the user's order, at most [trafficWidgetMaxRows], one per line of text, each
/// `id|name|background|text color|mode|state|title`: `state` is `b` interrupted, `d` disrupted, `n` normal (an
/// information alone is normal, as in the app's "Mes lignes"), `title` the first disruption's, else empty. A line
/// missing from [traffic] is normal: the backend lists the main lines and every disrupted one.
@visibleForTesting
String trafficWidgetRows(List<LineSummary> lines, List<LineTraffic> traffic) {
  final byLine = {for (final line in traffic) line.line.id: line};
  String state(LineTraffic? traffic) => switch (traffic?.severity) {
        DisruptionSeverity.blocking => 'b',
        DisruptionSeverity.disrupted => 'd',
        _ => 'n',
      };
  const order = {'b': 0, 'd': 1, 'n': 2};
  final rows = [
    for (final line in lines) (line: line, state: state(byLine[line.id]), traffic: byLine[line.id]),
  ];
  // The user's order within a state (Dart's sort isn't stable)
  final sorted = rows.indexed.toList()
    ..sort((a, b) {
      final byState = order[a.$2.state]!.compareTo(order[b.$2.state]!);
      return byState != 0 ? byState : a.$1.compareTo(b.$1);
    });
  return sorted.take(trafficWidgetMaxRows).map((entry) {
    final row = entry.$2;
    return [
      _field(row.line.id),
      _field(row.line.name),
      _field(row.line.color),
      _field(row.line.textColor),
      row.line.mode.name,
      row.state,
      row.state == 'n' ? '' : _field(row.traffic?.titles.firstOrNull),
    ].join('|');
  }).map((row) => '$row\n').join();
}

/// What the widget shows of [traffic] for [lines]: its rows, else why there is none, and when it was fetched
@visibleForTesting
Map<String, String?> trafficWidgetContent(List<LineSummary> lines, List<LineTraffic> traffic, DateTime now) {
  final rows = lines.isEmpty ? '' : trafficWidgetRows(lines, traffic);
  return {
    'traffic_rows': rows.isEmpty ? null : rows,
    'traffic_message': rows.isEmpty ? currentL10n.trafficWidgetNoLine : null,
    'traffic_updated': formatClock(now),
    'traffic_fetched_at': '${now.millisecondsSinceEpoch}',
  };
}

Future<void> _save(Map<String, String?> data) => Future.wait([
      for (final entry in data.entries) HomeWidget.saveWidgetData<String>(entry.key, entry.value),
    ]);

Future<void> _redraw() => HomeWidget.updateWidget(qualifiedAndroidName: trafficWidgetName);

/// Whether a "Mes lignes" widget is on the home screen
Future<bool> _placed() async =>
    (await HomeWidget.getInstalledWidgets()).any((widget) => widget.androidClassName == trafficWidgetName);

/// From the app (Android): keeps the favorite lines for the widget, and shows [traffic] on it when known (the app's own
/// `trafficProvider`: no request of its own). The lines are kept even without a widget placed, so that one placed
/// later knows them at once.
Future<void> syncTrafficWidget(List<Favorite> favorites, List<LineTraffic>? traffic) async {
  try {
    final lines = trafficWidgetLines(favorites);
    await HomeWidget.saveWidgetData<String>('traffic_lines', lines);
    if (!await _placed()) {
      return;
    }
    final parsed = readTrafficWidgetLines(lines);
    if (traffic != null) {
      await _save(trafficWidgetContent(parsed, traffic, DateTime.now()));
    } else if (parsed.isEmpty) {
      await _save({'traffic_rows': null, 'traffic_message': currentL10n.trafficWidgetNoLine});
    }
    await _redraw();
  } catch (e) {
    debugPrint('Traffic widget update failed: $e');
  }
}

/// The widget's refresh button and its periodic refresh (`WidgetRefreshWorker.kt`), in the background: fetches the
/// traffic for the lines the app last wrote. Nothing is fetched without a widget placed, nor without lines; a failure
/// keeps the rows it had, the widget saying so.
Future<void> refreshTrafficWidget(MobilityApi api) async {
  try {
    if (!await _placed()) {
      return;
    }
    final lines = readTrafficWidgetLines(await HomeWidget.getWidgetData<String>('traffic_lines'));
    final now = DateTime.now();
    if (lines.isEmpty) {
      await _save({'traffic_rows': null, 'traffic_message': currentL10n.trafficWidgetNoLine, 'traffic_updated': null});
    } else {
      try {
        await _save(trafficWidgetContent(lines, await api.traffic(), now));
      } catch (e) {
        debugPrint('Traffic widget refresh failed: $e');
        await _save({'traffic_updated': currentL10n.widgetFailedAt(formatClock(now))});
      }
    }
    await _redraw();
  } catch (e) {
    debugPrint('Traffic widget refresh failed: $e');
  }
}

/// Nothing could be fetched (no token, no network): the widget says so, with the rows it had
Future<void> failTrafficWidget() async {
  try {
    if (await _placed()) {
      await _save({'traffic_updated': currentL10n.widgetFailedAt(formatClock(DateTime.now()))});
      await _redraw();
    }
  } catch (e) {
    debugPrint('Traffic widget update failed: $e');
  }
}
