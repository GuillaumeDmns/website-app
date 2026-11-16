import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/platform/live_journey.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_labels.dart';
import '../stops/stop_screen.dart';

/// A departure followed from a stop's page, without a journey: which one, and what the real time last said of it
@immutable
class FollowedDeparture {
  const FollowedDeparture({
    required this.stopAreaId,
    required this.stopName,
    required this.line,
    required this.destination,
    required this.departure,
  });

  final String stopAreaId;
  final String stopName;
  final LineSummary line;
  final String destination;
  final Departure departure;

  FollowedDeparture at(Departure departure) => FollowedDeparture(
        stopAreaId: stopAreaId,
        stopName: stopName,
        line: line,
        destination: destination,
        departure: departure,
      );
}

/// Whether following a departure is offered: where the system shows it without the app (Android's notification, its
/// countdown run by the system)
final departureFollowAvailableProvider =
    Provider<bool>((ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// [followed] among the departures the stop gives now for its line and destination: the same train by its number,
/// else the same planned time (a delay moves the expected time, not that one), else the closest expected time within
/// 3 min (a metro has neither); null when it is no longer listed (it left)
Departure? findFollowed(List<Departure> candidates, Departure followed) {
  if (followed.trainNumber case final number?) {
    final same = candidates.where((candidate) => candidate.trainNumber == number).firstOrNull;
    if (same != null) {
      return same;
    }
  }
  if (followed.aimedTime case final aimed?) {
    final same = candidates
        .where((candidate) => candidate.aimedTime != null && candidate.aimedTime!.difference(aimed).abs() < const Duration(minutes: 1))
        .firstOrNull;
    if (same != null) {
      return same;
    }
  }
  Departure? closest;
  for (final candidate in candidates) {
    final gap = candidate.time.difference(followed.time).abs();
    if (gap <= const Duration(minutes: 3) && (closest == null || gap < closest.time.difference(followed.time).abs())) {
      closest = candidate;
    }
  }
  return closest;
}

/// What the system shows of [followed]: its line and destination, then where it leaves from, its platform and what the
/// real time says of it (late, cancelled, only scheduled); the time left is counted by the system from its departure
LiveDeparture departureLive(FollowedDeparture followed) {
  final departure = followed.departure;
  final late = departure.aimedTime == null ? 0 : departure.time.difference(departure.aimedTime!).inMinutes;
  return LiveDeparture(
    title: '${followed.line.label} · ${followed.destination}',
    status: [
      if (departure.cancelled) currentL10n.departureCancelled else currentL10n.followLeavesAt(formatClock(departure.time)),
      followed.stopName,
      ?platformLabel(followed.line, departure.platform),
      if (!departure.cancelled && late >= 1) currentL10n.goMinutesLate(late),
      if (!departure.cancelled && !departure.realtime) currentL10n.goScheduled,
    ].join(' · '),
    departureAt: departure.time,
    cancelled: departure.cancelled,
    mode: switch (followed.line.mode) {
      TransportMode.metro => 'metro',
      TransportMode.rer || TransportMode.transilien || TransportMode.ter => 'train',
      TransportMode.tram => 'tram',
      _ => 'bus',
    },
    line: (followed.line.name ?? '').isEmpty
        ? null
        : LiveJourneyLine(
            name: followed.line.name!,
            color: '#${followed.line.color ?? '666666'}',
            textColor: '#${followed.line.textColor ?? 'FFFFFF'}',
            mode: followed.line.mode.name,
          ),
    tone: departure.cancelled
        ? LiveJourneyTone.danger
        : late >= 3
            ? LiveJourneyTone.caution
            : LiveJourneyTone.fine,
  );
}

/// "Suivre ce départ" from a stop's page: one departure kept in the system's notification without a journey, with
/// "Arrêter". The stop's departures (stop-monitoring, every 30 s while the app is on screen: nothing more is asked for
/// it) say its delay, its platform, its cancellation; the system counts the time left and takes the notification away
/// once it left, with or without the app. Over on its own a minute after the departure, when GO starts (one live
/// notification), or when stopped.
class DepartureFollowController extends Notifier<FollowedDeparture?> {
  ProviderSubscription<AsyncValue<StopDepartures>>? _departures;
  Timer? _end;
  LiveDeparture? _shown;

  /// Followed this long after it left: boarding, a last look at the platform
  static const keptAfter = Duration(minutes: 1);

  @override
  FollowedDeparture? build() {
    ref.onDispose(_release);
    return null;
  }

  void follow(FollowedDeparture departure) {
    _release();
    ref.read(liveJourneyProvider).prepare();
    state = departure;
    _departures = ref.listen(stopDeparturesProvider(departure.stopAreaId), (_, departures) => _onDepartures(departures.value));
    _publish();
  }

  /// "Arrêter", in the app or in the notification
  void stop() {
    if (state == null) {
      return;
    }
    handOver();
    ref.read(liveJourneyProvider).stop();
  }

  /// GO starts: the notification is its journey's
  void handOver() {
    _release();
    state = null;
  }

  void _release() {
    _departures?.close();
    _departures = null;
    _end?.cancel();
    _end = null;
    _shown = null;
  }

  void _onDepartures(StopDepartures? departures) {
    final followed = state;
    if (departures == null || followed == null) {
      return;
    }
    final candidates = [
      for (final row in departures.lines)
        if (row.line.id == followed.line.id && row.destination == followed.destination) ...row.departures,
    ];
    final latest = findFollowed(candidates, followed.departure);
    if (latest != null && latest != followed.departure) {
      state = followed.at(latest);
      _publish();
    }
  }

  void _publish() {
    final followed = state;
    if (followed == null) {
      return;
    }
    final left = followed.departure.time.add(keptAfter).difference(DateTime.now());
    _end?.cancel();
    if (left <= Duration.zero) {
      stop();
      return;
    }
    _end = Timer(left, stop);
    final live = departureLive(followed);
    if (live != _shown) {
      _shown = live;
      ref.read(liveJourneyProvider).followDeparture(live);
    }
  }
}

final departureFollowProvider = NotifierProvider<DepartureFollowController, FollowedDeparture?>(DepartureFollowController.new);
