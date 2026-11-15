import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/routes.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/map/map_view.dart';
import '../../core/widgets/line_badge.dart';
import '../traffic/disruption_widgets.dart';

/// From how close the map shows the stops of the part it shows, in meters per logical pixel: a neighbourhood on the
/// screen (MapLibre's zoom 15 around Paris). Further out they would cover the map.
const mapStopsMetersPerPixel = 1.65;

/// Stops asked for the map at most: the closest ones to its center (the backend's limit)
const mapStopsLimit = 50;

/// The stops to ask for a [MapView]: around its center rounded to about 100 m (small moves of the map ask nothing
/// new), as far as its corners; null when the map shows too much for them, or isn't known yet
({double lat, double lon, int radius})? mapStopsQuery(MapView? view) {
  if (view == null || view.metersPerPixel > mapStopsMetersPerPixel) {
    return null;
  }
  double round(double value) => (value * 1000).roundToDouble() / 1000;
  // To the next 100 m, and 100 m more for the rounded center; the backend looks at most 2 km around
  final radius = ((view.radius / 100).ceil() + 1) * 100;
  return (lat: round(view.center.latitude), lon: round(view.center.longitude), radius: radius.clamp(100, 2000));
}

/// The stop areas of the part of the map shown, with their lines, once it is close enough ([mapStopsMetersPerPixel]);
/// none further out. From the GTFS only (`/api/v2/nearby`): no real-time quota. While the stops of a new view are
/// fetched, the previous ones stay (the provider keeps its last value): the markers don't blink as the map moves.
final mapStopsProvider = FutureProvider.autoDispose<List<StopAreaSummary>>((ref) async {
  final query = ref.watch(mapViewProvider.select(mapStopsQuery));
  if (query == null) {
    return const [];
  }
  return ref.mobilityApi.nearby(query.lat, query.lon, radius: query.radius, limit: mapStopsLimit);
});

/// The stop of [departures] for its marker: with the lines of its departures when it comes without its own
StopAreaSummary markerStop(StopDepartures departures) => departures.stop.lines.isNotEmpty
    ? departures.stop
    : departures.stop.copyWith(lines: [for (final line in departures.lines) line.line]);

/// The lines a stop's marker shows, the heaviest modes first (trains, metro, tram, bus, night bus), then by name
List<LineSummary> markerLines(Iterable<LineSummary> lines) {
  int rank(TransportMode mode) => switch (mode) {
    TransportMode.rer || TransportMode.transilien || TransportMode.ter => 0,
    TransportMode.metro => 1,
    TransportMode.tram => 2,
    TransportMode.bus => 3,
    TransportMode.noctilien => 4,
  };
  final unique = {for (final line in lines) line.id.isEmpty ? '${line.mode.name}-${line.name}' : line.id: line}.values.toList();
  return unique
    ..sort((a, b) {
      final byMode = rank(a.mode).compareTo(rank(b.mode));
      if (byMode != 0) {
        return byMode;
      }
      final (nameA, nameB) = (a.name ?? '', b.name ?? '');
      final (numberA, numberB) = (int.tryParse(nameA), int.tryParse(nameB));
      return numberA != null && numberB != null ? numberA.compareTo(numberB) : nameA.compareTo(nameB);
    });
}

/// One marker per stop of [stops] on the map, with its lines among [shows] (every line by default; a stop without any
/// of them is left out): a tap opens the stop. A stop given twice has one marker; the last ones are drawn on top.
/// [severities] marks the interrupted lines. On the page of the stop [opened], its own marker opens nothing and the
/// others take its place (going back leaves the stops, not through each one looked at).
List<MapPin> stopPins(
  BuildContext context,
  Iterable<StopAreaSummary> stops, {
  bool Function(TransportMode mode)? shows,
  Map<String, DisruptionSeverity> severities = const {},
  String? opened,
}) {
  final scheme = Theme.of(context).colorScheme;
  final pins = <String, MapPin>{};
  for (final stop in stops) {
    final lines = markerLines(stop.lines.where((line) => shows == null || shows(line.mode)));
    if (lines.isEmpty && (shows != null || stop.lines.isNotEmpty)) {
      continue;
    }
    final point = LatLng(stop.lat, stop.lon);
    final open = stop.id == opened
        ? null
        : () => opened == null ? context.push(Routes.stop(stop.id)) : context.pushReplacement(Routes.stop(stop.id));
    // Drawn again last: on top
    pins.remove(stop.id);
    if (lines.isEmpty) {
      // Its lines unknown: a plain dot
      pins[stop.id] = MapPin(point: point, color: scheme.primary, icon: Icons.directions_transit, size: 22, label: stop.name, onTap: open);
      continue;
    }
    final shown = lines.take(StopMarker.maxLines).toList();
    final more = lines.length - shown.length;
    final interrupted = {for (final line in shown) if (severities[line.id] == DisruptionSeverity.blocking) line.id};
    pins[stop.id] = MapPin(
      point: point,
      color: scheme.primary,
      label: stop.name,
      onTap: open,
      above: true,
      childSize: StopMarker.sizeOf(shown, more),
      // The same look for the same lines, whatever the stop
      image: 'stop-${shown.map((line) => '${line.mode.name}:${line.name}:${line.color}${interrupted.contains(line.id) ? '!' : ''}').join(',')}+$more',
      child: StopMarker(lines: shown, more: more, interrupted: interrupted),
    );
  }
  return pins.values.toList();
}

/// A stop on the map: its lines' badges in a dark box pointing at it, `+2` for those it has no room for, a red mark
/// on an interrupted line. Dark in both themes: the map stays light.
class StopMarker extends StatelessWidget {
  const StopMarker({super.key, required this.lines, this.more = 0, this.interrupted = const {}});

  final List<LineSummary> lines;

  /// Lines left out
  final int more;

  /// Ids of the lines whose traffic is interrupted
  final Set<String> interrupted;

  /// Badges at most, the heaviest modes first ([markerLines])
  static const maxLines = 3;

  static const _badge = 18.0;
  static const _pointer = 6.0;
  static const _box = Color(0xFF101215);

  /// The box a marker of [lines] is drawn in, its point at the bottom center
  static Size sizeOf(List<LineSummary> lines, int more) {
    double width(LineSummary line) => switch (line.mode) {
      TransportMode.metro || TransportMode.rer || TransportMode.transilien || TransportMode.ter => _badge,
      // Up to four characters (`N122`, `T3a`)
      TransportMode.tram || TransportMode.bus || TransportMode.noctilien => _badge * 1.75,
    };
    final badges = lines.fold(0.0, (sum, line) => sum + width(line)) + (lines.length - 1) * 3;
    // Room for the red mark over the last badge's corner
    return Size(badges + (more > 0 ? 22 : 0) + 12, _badge + 6 + _pointer + 4);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _box,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, line) in lines.indexed) ...[
                if (index > 0) const SizedBox(width: 3),
                WithSeverity(
                  severity: interrupted.contains(line.id) ? DisruptionSeverity.blocking : null,
                  dotSize: 11,
                  child: LineBadge(line, size: _badge),
                ),
              ],
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: Text(
                    '+$more',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1),
                  ),
                ),
            ],
          ),
        ),
        CustomPaint(size: const Size(10, _pointer), painter: _PointerPainter()),
      ],
    );
  }
}

/// The marker's point, under its box
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = StopMarker._box);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => false;
}
