import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../journey/journey_request.dart';
import 'go_tracker.dart';

/// A journey followed in GO mode
@immutable
class GoState {
  const GoState({
    required this.tracker,
    required this.request,
    required this.progress,
    required this.startedAt,
    required this.plannedArrival,
    this.muted = false,
    this.keepAwake = false,
    this.position,
    this.walkSpeed,
    this.vehicle,
    this.vehicleStep,
    this.realtimeDepartures = false,
    this.alert,
    this.alertAt,
    this.recalculating = false,
    this.error,
    this.retained,
    this.recalculateAt,
  });

  final GoTracker tracker;

  /// Destination and options, to recalculate
  final JourneyRequest request;
  final GoProgress progress;
  final DateTime startedAt;

  /// Arrival planned when GO was started (kept through recalculations and departures chosen), for the arrival summary
  final DateTime plannedArrival;

  /// No sound nor vibration for the alerts
  final bool muted;

  /// The screen stays on
  final bool keepAwake;

  /// Last position fix
  final LatLng? position;

  /// The user's walking pace (m/s), from the fixes' speeds while walking; null until known
  final double? walkSpeed;

  /// Real-time departure of the planned vehicle of the ride [vehicleStep] (the next one)
  final Departure? vehicle;
  final int? vehicleStep;

  /// The departures of the ride [vehicleStep] come with real time: one gone from them has left. Without it, only the
  /// schedule tells when a vehicle should come.
  final bool realtimeDepartures;

  /// Last alert given, and when
  final GoAlert? alert;
  final DateTime? alertAt;
  final bool recalculating;

  /// Last recalculation failure
  final String? error;

  /// The vehicle of the ride [step] was missed or cancelled and the next one was taken on its own: how much later
  /// the arrival is. Kept while the user waits for it.
  final ({int step, Duration later, bool cancelled})? retained;

  /// Off the way: when the journey is recalculated on its own, unless the user does it first or ignores it
  final DateTime? recalculateAt;

  JourneyOption get journey => tracker.journey;

  /// Vehicle of the current ride (null when the next ride is not the current step)
  Departure? get currentVehicle => vehicleStep == progress.step ? vehicle : null;

  GoState copyWith({
    GoTracker? tracker,
    GoProgress? progress,
    bool? muted,
    bool? keepAwake,
    LatLng? position,
    double? walkSpeed,
    Departure? Function()? vehicle,
    int? Function()? vehicleStep,
    bool? realtimeDepartures,
    GoAlert? alert,
    DateTime? alertAt,
    bool? recalculating,
    String? Function()? error,
    ({int step, Duration later, bool cancelled})? Function()? retained,
    DateTime? Function()? recalculateAt,
  }) =>
      GoState(
        tracker: tracker ?? this.tracker,
        request: request,
        progress: progress ?? this.progress,
        startedAt: startedAt,
        plannedArrival: plannedArrival,
        muted: muted ?? this.muted,
        keepAwake: keepAwake ?? this.keepAwake,
        position: position ?? this.position,
        walkSpeed: walkSpeed ?? this.walkSpeed,
        vehicle: vehicle != null ? vehicle() : this.vehicle,
        vehicleStep: vehicleStep != null ? vehicleStep() : this.vehicleStep,
        realtimeDepartures: realtimeDepartures ?? this.realtimeDepartures,
        alert: alert ?? this.alert,
        alertAt: alertAt ?? this.alertAt,
        recalculating: recalculating ?? this.recalculating,
        error: error != null ? error() : this.error,
        retained: retained != null ? retained() : this.retained,
        recalculateAt: recalculateAt != null ? recalculateAt() : this.recalculateAt,
      );
}

/// How the position fixes of GO come, for the development builds: is the device's GPS giving a fix every second?
@immutable
class GoFixStats {
  const GoFixStats({required this.at, required this.accuracy, this.interval});

  /// When the last fix came
  final DateTime at;

  /// Its accuracy (m)
  final double accuracy;

  /// Mean time between the last fixes, null after the first one
  final Duration? interval;
}

class GoFixStatsController extends Notifier<GoFixStats?> {
  final _times = <DateTime>[];

  @override
  GoFixStats? build() => null;

  void record(DateTime at, double accuracy) {
    _times.add(at);
    if (_times.length > 6) {
      _times.removeAt(0);
    }
    state = GoFixStats(
      at: at,
      accuracy: accuracy,
      interval: _times.length < 2 ? null : _times.last.difference(_times.first) ~/ (_times.length - 1),
    );
  }

  void clear() {
    _times.clear();
    state = null;
  }
}

final goFixStatsProvider = NotifierProvider<GoFixStatsController, GoFixStats?>(GoFixStatsController.new);
