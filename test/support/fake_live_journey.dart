import 'dart:ui';

import 'package:website_app/core/platform/live_journey.dart';

/// The system's notification of the tests: what it was given, "Terminer" / "Arrêter" tapped on demand
class FakeLiveJourney implements LiveJourney {
  final updates = <LiveJourneyUpdate>[];
  final departures = <LiveDeparture>[];
  int stops = 0;
  VoidCallback? _stop;

  void tapStop() => _stop?.call();

  @override
  Future<void> followDeparture(LiveDeparture departure) async => departures.add(departure);

  @override
  Future<void> update(LiveJourneyUpdate update) async => updates.add(update);

  @override
  Future<void> alert(String title, String? body) async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> keepScreenOn(bool on) async {}

  @override
  void onStop(VoidCallback stop) => _stop = stop;

  @override
  Future<bool> stopRequested() async => false;
}
