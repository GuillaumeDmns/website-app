import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/platform/app_shown.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/punctuality.dart';
import '../../core/utils/refresh.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../remote_config/remote_config.dart';

/// Vehicles of a line and when they were fetched, refreshed every minute while shown, never with the app off screen
/// (the backend keeps them a minute: the estimated-timetable quota is small)
final lineVehiclesProvider = FutureProvider.autoDispose.family<({List<Vehicle> vehicles, DateTime fetchedAt}), String>((ref, lineId) async {
  // Switched off by the backend (its quota in danger): nothing asked
  if (ref.watch(featureDisabledProvider('vehicles'))) {
    return (vehicles: const <Vehicle>[], fetchedAt: DateTime.now());
  }
  ref.refreshEvery(const Duration(seconds: 60));
  final vehicles = await ref.mobilityApi.lineVehicles(lineId);
  return (vehicles: vehicles, fetchedAt: DateTime.now());
});

/// Ticks every second while a line's vehicles are shown and the app is on screen, so that they glide along their path
final vehicleClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => clockEvery(const Duration(seconds: 1), shown: ref.watch(appShownProvider)),
);

/// Where a vehicle is on its branch's path
///
/// [heading]: its direction of travel, in degrees clockwise from north
typedef VehiclePlacement = ({LatLng point, double heading});

/// Progress of a vehicle between its two stops at [now]: it keeps moving between two fetches, at the pace given by
/// the progress and the expected time at the next stop when fetched
double vehicleProgress(Vehicle vehicle, DateTime fetchedAt, DateTime now) {
  if (vehicle.fromStopId == null || vehicle.progress >= 1) {
    return 1;
  }
  final remainingAtFetch = vehicle.expectedAt.difference(fetchedAt).inMilliseconds;
  if (remainingAtFetch <= 0) {
    return 1;
  }
  final segment = remainingAtFetch / (1 - vehicle.progress);
  final remaining = vehicle.expectedAt.difference(now).inMilliseconds;
  return (1 - remaining / segment).clamp(vehicle.progress, 1.0);
}

/// How long a vehicle stands at a stop when the real time gives no departure there
Duration standingTime(TransportMode mode) => switch (mode) {
      TransportMode.rer || TransportMode.transilien || TransportMode.ter => const Duration(seconds: 40),
      TransportMode.metro || TransportMode.tram => const Duration(seconds: 20),
      _ => const Duration(seconds: 15),
    };

/// When [vehicle] leaves the stop of its call [index]: the departure the real time gives, else after [standingTime];
/// where its trip starts, at the time given (its departure)
DateTime leavesAt(Vehicle vehicle, int index, TransportMode mode) {
  final call = vehicle.calls[index];
  if (call.departureAt case final departure?) {
    return departure;
  }
  return index == 0 && vehicle.fromStopId == null ? call.expectedAt : call.expectedAt.add(standingTime(mode));
}

/// [vehicle] at [now], as fetched at [fetchedAt]: along its segment at the pace of the fetch ([vehicleProgress]), then
/// standing at its next stop until it leaves ([leavesAt]), then on to its following stops on their expected times, as
/// far as its calls go; the next fetch puts it back where the real time says. Calls at stops [serves] doesn't know
/// (not on the branch drawn) are skipped.
({Vehicle vehicle, double progress}) vehicleAt(
  Vehicle vehicle,
  DateTime fetchedAt,
  DateTime now,
  TransportMode mode, {
  bool Function(String stopId)? serves,
}) {
  var progress = vehicleProgress(vehicle, fetchedAt, now);
  final calls = [
    for (final (index, call) in vehicle.calls.indexed)
      if (index == 0 || (serves?.call(call.stopId) ?? true)) call,
  ];
  if (calls.length < 2 || calls.first.stopId != vehicle.toStopId) {
    return (vehicle: vehicle, progress: progress);
  }
  var current = vehicle;
  var ahead = calls;
  while (ahead.length >= 2) {
    final leaves = leavesAt(current.copyWith(calls: ahead), 0, mode);
    if (!now.isAfter(leaves)) {
      break;
    }
    final left = ahead.first;
    final next = ahead[1];
    final ride = next.expectedAt.difference(leaves).inMilliseconds;
    progress = ride <= 0 ? 1.0 : (now.difference(leaves).inMilliseconds / ride).clamp(0.0, 1.0);
    ahead = ahead.sublist(1);
    current = current.copyWith(
      fromStopId: left.stopId,
      toStopId: next.stopId,
      toStopName: next.stopName,
      expectedAt: next.expectedAt,
      delaySeconds: next.delaySeconds ?? current.delaySeconds,
      progress: progress,
      calls: ahead,
    );
  }
  return (vehicle: current, progress: progress);
}

/// `à quai`, `à l'arrêt` for a bus
String atStopLabel(TransportMode mode) => mode.hasPlatforms ? currentL10n.vehicleAtPlatform : currentL10n.vehicleAtStop;

/// Path of a branch with the distance of each of its stops along it, to place vehicles
class BranchPath {
  BranchPath(LineBranch branch)
      : line = MeasuredPolyline(
            branch.shape.isNotEmpty ? shapePoints(branch.shape) : [for (final stop in branch.stops) LatLng(stop.lat, stop.lon)]),
        stopIds = [for (final stop in branch.stops) stop.id] {
    var minAlong = 0.0;
    for (final stop in branch.stops) {
      final along = line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong)?.along ?? minAlong;
      stopAlongs.add(along);
      minAlong = along;
    }
  }

  final MeasuredPolyline line;
  final List<String> stopIds;
  final List<double> stopAlongs = [];

  /// The stretches of the path through its stops not in [served], each from the served stop before them to the one
  /// after (the path's end where there is none): what it adds to a path drawn through [served]
  List<List<LatLng>> partsOff(Set<String> served) {
    final parts = <List<LatLng>>[];
    var i = 0;
    while (i < stopIds.length) {
      if (served.contains(stopIds[i])) {
        i++;
        continue;
      }
      final start = i;
      while (i < stopIds.length && !served.contains(stopIds[i])) {
        i++;
      }
      final from = start == 0 ? 0.0 : stopAlongs[start - 1];
      final to = i >= stopIds.length ? line.length : stopAlongs[i];
      if (to > from) {
        parts.add(MeasuredPolyline(line.split(to).$1).split(from).$2);
      }
    }
    return parts;
  }

  /// Where [vehicle] is at [progress] between its two stops and which way it goes; null when they are not on this branch
  VehiclePlacement? place(Vehicle vehicle, double progress) {
    final along = alongOf(vehicle, progress)?.along;
    if (along == null) {
      return null;
    }
    // The way ahead around it (the branch's direction at a stop where it waits), over 100 m: GTFS shapes often make a
    // small hook at stations, which turned the pointer sideways
    const around = 50.0;
    final ahead = math.min(along + around, line.length);
    final behind = math.max(ahead - 2 * around, 0.0);
    return (point: line.pointAt(along), heading: bearingBetween(line.pointAt(behind), line.pointAt(ahead)));
  }

  /// How far along the path [vehicle] is at [progress] between the stop it left ([from], meters along) and the next
  /// one ([to]); null when they are not on this branch
  ({double along, double from, double to})? alongOf(Vehicle vehicle, double progress) {
    final to = stopIds.indexOf(vehicle.toStopId);
    if (to < 0 || line.isEmpty) {
      return null;
    }
    // Stop just left: in this branch when the vehicle serves it, the previous stop otherwise
    final left = vehicle.fromStopId == null ? -1 : stopIds.lastIndexOf(vehicle.fromStopId!, to);
    final from = vehicle.fromStopId == null ? to : left >= 0 ? left : math.max(0, to - 1);
    return (
      along: stopAlongs[from] + (stopAlongs[to] - stopAlongs[from]) * progress,
      from: stopAlongs[from],
      to: stopAlongs[to],
    );
  }

  /// How far along the path [stop] is, from [minAlong] meters on; null when it is more than [within] meters off the
  /// path (a stop this branch doesn't run by)
  double? alongStop(StopRef stop, {double minAlong = 0, double within = 600}) {
    final projection = line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong);
    return projection == null || projection.distance > within ? null : projection.along;
  }
}

/// The stops of [branch], a stop area served twice in a row (two of its quays, as the bus 38 at Denfert-Rochereau)
/// once
List<StopRef> stopsOnce(LineBranch branch) => [
      for (final (index, stop) in branch.stops.indexed)
        if (index == 0 || branch.stops[index - 1].id != stop.id) stop,
    ];

/// Whether a vehicle at [progress] stands at a stop: waiting where its trip starts, or arrived at its next stop
bool isAtStop(Vehicle vehicle, double progress) => vehicle.fromStopId == null || progress >= 1;

/// How on time a vehicle is (the vehicle sheet and the stop list say it; its marker doesn't)
enum Punctuality {
  /// No delay given
  unknown,
  onTime,
  late;

  /// Late from [shownOffset], like the delays shown in the vehicle sheet (a vehicle has no real-time status)
  static Punctuality of(Vehicle vehicle) => switch (vehicle.delaySeconds) {
        null => unknown,
        final delay when showsLate(Duration(seconds: delay)) => late,
        _ => onTime,
      };
}

/// A vehicle as a train seen from above (design 2c, "Rame", shape L): a slim body of the line's color along the track,
/// ringed with white, its cab rounded at the front with a dark windscreen (the way it goes), bands on its roof, its
/// back square; drawn pointing up (the map turns it the way the vehicle goes). A white bar across it when it stands
/// at a stop; larger over a halo of the line's color when [selected] (its sheet open or followed). Whether it is late
/// doesn't show on it.
class VehicleCapsule extends StatelessWidget {
  const VehicleCapsule({
    super.key,
    required this.line,
    this.atStop = false,
    this.selected = false,
    this.faded = false,
    this.scale = 1,
    this.arrow = false,
  });

  final LineSummary line;
  final bool atStop;
  final bool selected;

  /// The stop list's: a wider body with a chevron to its front instead of its roof, the way it goes read at a
  /// glance at its small size
  final bool arrow;

  /// Left out by the line page's filter: still on the map, faded
  final bool faded;

  /// Smaller in the stop list
  final double scale;

  /// Its box, square: the halo of a selected one, else room for the bar and a 44 dp tap target
  static double boxSize({bool selected = false, double scale = 1}) => (selected ? 56 : 44) * scale;

  /// The name of its image on the map, one per line and look
  static String imageName(LineSummary line, {required bool atStop, required bool selected, bool faded = false}) =>
      'capsule-${line.id}-${line.color}-${atStop ? 'stop' : 'run'}-${selected ? 'selected' : faded ? 'faded' : 'normal'}';

  @override
  Widget build(BuildContext context) {
    final size = boxSize(selected: selected, scale: scale);
    final capsule = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _CapsulePainter(
          color: parseHexColor(line.color, Colors.grey.shade700),
          atStop: atStop,
          selected: selected,
          scale: scale,
          arrow: arrow,
        ),
      ),
    );
    return faded && !selected ? Opacity(opacity: 0.35, child: capsule) : capsule;
  }
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter({
    required this.color,
    required this.atStop,
    required this.selected,
    required this.scale,
    required this.arrow,
  });

  /// Its edges, dark on every map
  static const ink = Color(0xFF101215);

  final Color color;
  final bool atStop;
  final bool selected;
  final double scale;
  final bool arrow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final k = selected ? 1.25 : 1.0;
    final w = (arrow ? 7 : 5) * k;
    final hh = 16 * k;
    final body = bodyPath(w, hh, k);

    if (selected) {
      canvas.drawCircle(Offset.zero, 26, Paint()..color = color.withValues(alpha: 0.3));
    }
    if (atStop) {
      final bar = RRect.fromLTRBR(-13 * k, -2.5, 13 * k, 2.5, const Radius.circular(2.5));
      canvas.drawRRect(bar, Paint()..color = Colors.white);
      canvas.drawRRect(
        bar,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    // A white ring: it stands out of its line, a light one too
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 6 : 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(body, Paint()..color = color);
    canvas.drawPath(
      body,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
    if (arrow) {
      // A chevron to its front, dark on a light line, white on a dark one
      canvas.drawPath(
        Path()
          ..moveTo(-w * 0.55, -hh + 9 * k)
          ..lineTo(0, -hh + 4.5 * k)
          ..lineTo(w * 0.55, -hh + 9 * k),
        Paint()
          ..color = markOn(color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    // The windscreen across its cab
    final top = -hh + 2 * k;
    canvas.drawPath(
      Path()
        ..moveTo(-w * 0.72, top + 3 * k)
        ..quadraticBezierTo(0, top - 1.6 * k, w * 0.72, top + 3 * k)
        ..lineTo(w * 0.72, top + 5 * k)
        ..quadraticBezierTo(0, top + 1.4 * k, -w * 0.72, top + 5 * k)
        ..close(),
      Paint()..color = ink,
    );
    // Bands on its roof
    final band = Paint()..color = ink.withValues(alpha: 0.55);
    for (final y in const [-4.0, 1.0, 6.0, 11.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(-w * 0.45, (y - 1.4) * k, w * 0.45, (y + 1.4) * k, Radius.circular(0.8 * k)),
        band,
      );
    }
  }

  /// Its body, [w] half wide and [hh] half long, pointing up: its cab rounded at the front, its back square with
  /// rounded corners
  static Path bodyPath(double w, double hh, double k) {
    final nose = 6.5 * k;
    final back = 2 * k;
    return Path()
      ..moveTo(-w, hh - back)
      ..lineTo(-w, -hh + nose)
      ..cubicTo(-w, -hh + nose * 0.35, -w * 0.45, -hh, 0, -hh)
      ..cubicTo(w * 0.45, -hh, w, -hh + nose * 0.35, w, -hh + nose)
      ..lineTo(w, hh - back)
      ..quadraticBezierTo(w, hh, w - back, hh)
      ..lineTo(-w + back, hh)
      ..quadraticBezierTo(-w, hh, -w, hh - back)
      ..close();
  }

  @override
  bool shouldRepaint(_CapsulePainter old) =>
      old.color != color || old.atStop != atStop || old.selected != selected || old.scale != scale || old.arrow != arrow;
}

/// What is drawn on a vehicle of [color]: dark on a light line, white on a dark one
Color markOn(Color color) => color.computeLuminance() > 0.35 ? const Color(0xFF101215) : Colors.white;

/// Over the selected vehicle on the map: its next stop and when it gets there (`République · 1 min`, `· à quai`), and
/// its delay. Dark on every map, its tip [gap] above the vehicle's middle, in a box of [sizeOf] (the map pin stands it
/// on its point by its bottom).
class VehicleCallout extends StatelessWidget {
  const VehicleCallout({super.key, required this.stop, required this.when, this.delay, this.fontFamily});

  final String stop;

  /// The app's (Inter), the same as [sizeOf] measured with
  final String? fontFamily;
  final String when;

  /// `3 min de retard`, when late
  final String? delay;

  /// From the vehicle's middle to the tip, clear of a selected capsule
  static const gap = 30.0;
  static const _arrow = 6.0;
  static const _style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2);

  static const _background = Color(0xFF101215);

  /// The name of its image on the map
  String get imageName => 'vehicle-callout-$stop-$when-$delay';

  /// Its text, the same measured and drawn: nothing inherited (Material's letter spacing widened it past its box)
  static TextSpan _text({required String stop, required String when, String? delay, String? fontFamily}) => TextSpan(
        style: _style.copyWith(color: const Color(0xFFECEEF1), fontFamily: fontFamily, letterSpacing: 0),
        children: [
          TextSpan(text: stop),
          TextSpan(
            text: '   $when',
            style: const TextStyle(color: Color(0xFF9AA1AC), fontWeight: FontWeight.w500),
          ),
          if (delay != null) TextSpan(text: '   $delay', style: const TextStyle(color: Color(0xFFF5A524))),
        ],
      );

  /// Its box: the bubble as wide as its text, its arrow, the gap under it
  static Size sizeOf({required String stop, required String when, String? delay, String? fontFamily}) {
    final painter = TextPainter(
      text: _text(stop: stop, when: when, delay: delay, fontFamily: fontFamily),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * 10 + 4;
    final height = painter.height + 2 * 6 + _arrow + gap;
    painter.dispose();
    return Size(width.ceilToDouble(), height.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _background,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Color(0x24FFFFFF), spreadRadius: 1),
                  BoxShadow(color: Color(0x73000000), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text.rich(
                  _text(stop: stop, when: when, delay: delay, fontFamily: fontFamily),
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
            CustomPaint(size: const Size(12, _arrow), painter: _ArrowPainter(_background)),
          ],
        ),
      );
}

/// The callout's tip, pointing down
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close(),
        Paint()..color = color,
      );

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// When [vehicle] gets to its next stop: `1 min` (still on its way when due), `à quai` (`à l'arrêt`) when there, its
/// time an hour away or more
String vehicleWhen(Vehicle vehicle, DateTime now, TransportMode mode, {required bool atStop}) {
  if (atStop) {
    return atStopLabel(mode);
  }
  final minutes = vehicle.expectedAt.difference(now).inSeconds / 60;
  return minutes < 60 ? currentL10n.minutesShort(math.max(1, minutes.ceil())) : formatClock(vehicle.expectedAt);
}

/// Its delay in words, `3 min de retard`, when late ([Punctuality.late])
String? vehicleDelay(Vehicle vehicle) =>
    Punctuality.of(vehicle) == Punctuality.late ? currentL10n.goMinutesLate((vehicle.delaySeconds! / 60).round()) : null;

/// `→ Saint-Denis - Pleyel · Madeleine dans 2 min`, `… · Madeleine à quai`
String vehicleLabel(Vehicle vehicle, DateTime now, TransportMode mode) {
  final minutes = vehicle.expectedAt.difference(now).inSeconds / 60;
  final next = vehicle.toStopName ?? '';
  final when = minutes < 0.5
      ? atStopLabel(mode)
      : minutes < 60
          ? currentL10n.inMinutes(minutes.ceil())
          : formatClock(vehicle.expectedAt);
  return '→ ${vehicle.destination ?? ''} · $next $when';
}
