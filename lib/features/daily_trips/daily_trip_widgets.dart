import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../go/go_controller.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/refresh.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorites_controller.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_request.dart';
import '../journey/widgets/journey_card.dart';
import 'daily_trips.dart';
import '../../app/theme.dart';

typedef RideSpanKey = ({String lineId, String from, String to});

/// First and last rides of a line between two stops tonight (GTFS, no real-time call), refreshed every 15 min while
/// shown: the service day changes at night
final rideSpanProvider = FutureProvider.autoDispose.family<RideSpan, RideSpanKey>((ref, key) async {
  ref.refreshEvery(const Duration(minutes: 15));
  return ref.watch(mobilityApiProvider).lineRideSpan(key.lineId, from: key.from, to: key.to);
});

/// Spans of the rides of a trip for [lastTripAlert], from a widget (watched)
RideSpan? Function(JourneySection ride) watchSpans(WidgetRef ref) => (ride) {
      final lineId = ride.line?.id;
      final from = ride.from?.stopAreaId;
      final to = ride.to?.stopAreaId;
      if (lineId == null || lineId.isEmpty || from == null || to == null) {
        return null;
      }
      return ref.watch(rideSpanProvider((lineId: lineId, from: from, to: to))).value;
    };

/// A last ride this close is announced
const lastRideWarning = Duration(minutes: 60);

/// `métro`, `RER`, `train`, `tram`, `bus`
String modeNoun(TransportMode mode) => switch (mode) {
      TransportMode.metro => currentL10n.modeNounMetro,
      TransportMode.rer => 'RER',
      TransportMode.transilien || TransportMode.ter => currentL10n.modeNounTrain,
      TransportMode.tram => currentL10n.modeNounTram,
      TransportMode.bus || TransportMode.noctilien => currentL10n.modeNounBus,
    };

/// `Dernier métro 1 à 00:41 · partir avant 00:33`, `Service terminé · reprise vers 05:24`; null when there is
/// nothing to say yet (the last ride more than an hour ahead)
String? lastTripText(LastTripAlert? alert, DateTime now) {
  if (alert == null) {
    return null;
  }
  if (alert.over) {
    return [currentL10n.lastRideOver, if (alert.resumesAt case final at?) currentL10n.lastRideResumes(formatClock(at))].join(' · ');
  }
  if (alert.leaveBy!.difference(now) > lastRideWarning) {
    return null;
  }
  final line = alert.ride.line;
  return [
    if (line != null && alert.lastDeparture != null)
      currentL10n.lastRideOf(modeNoun(line.mode), line.name ?? '', formatClock(alert.lastDeparture!)),
    currentL10n.lastRideLeaveBefore(formatClock(alert.leaveBy!)),
  ].join(' · ');
}

/// "Maison" or "Travail" when [point] is one of them, else its name
String tripPlaceName(JourneyPoint? point, List<Favorite> favorites) {
  if (point == null) {
    return '';
  }
  for (final favorite in favorites) {
    if ((favorite.kind == FavoriteKind.home || favorite.kind == FavoriteKind.work) && favorite.lat != null && favorite.lon != null &&
        metersBetween(LatLng(point.lat, point.lon), LatLng(favorite.lat!, favorite.lon!)) < 200) {
      return favorite.kind == FavoriteKind.home ? currentL10n.home : currentL10n.work;
    }
  }
  return point.name;
}

/// Whether [point] is the saved home
bool _isHome(JourneyPoint? point, List<Favorite> favorites) => tripPlaceName(point, favorites) == currentL10n.home;

/// A trip from home is shown the way back in the afternoon, one to home in the morning
bool startsReversed(DailyTrip trip, List<Favorite> favorites, DateTime now) {
  final afternoon = now.hour >= 14;
  return (afternoon && _isHome(trip.start, favorites)) || (!afternoon && _isHome(trip.end, favorites));
}

/// The daily trips on the home page; with home and work saved but no trip between them, an invitation to choose one
class DailyTripsSection extends ConsumerWidget {
  const DailyTripsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(dailyTripsProvider).value ?? const <DailyTrip>[];
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    final home = favorites.where((favorite) => favorite.kind == FavoriteKind.home).firstOrNull;
    final work = favorites.where((favorite) => favorite.kind == FavoriteKind.work).firstOrNull;
    final names = [for (final trip in trips) {tripPlaceName(trip.start, favorites), tripPlaceName(trip.end, favorites)}];
    final commuteSaved = names.any((pair) => pair.contains(context.l10n.home) && pair.contains(context.l10n.work));

    if (trips.isEmpty && (home == null || work == null || commuteSaved)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.l10n.dailyTripsTitle),
        for (final trip in trips)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: DailyTripCard(key: ValueKey(trip.id), trip: trip)),
        if (home != null && work != null && !commuteSaved) _CommuteHint(home: home, work: work),
      ],
    );
  }
}

class _CommuteHint extends ConsumerWidget {
  const _CommuteHint({required this.home, required this.work});

  final Favorite home;
  final Favorite work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBubble(Icons.route, color: theme.colorScheme.primary, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Text(context.l10n.dailyTripHint(context.l10n.home, context.l10n.work), style: theme.textTheme.bodyMedium)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(context.l10n.dailyTripChoose),
              onPressed: () => context.push(Routes.journey(ref.read(journeyPreferencesProvider).apply(JourneyRequest(
                    from: favoritePlace(home),
                    to: favoritePlace(work),
                  )))),
            ),
          ),
        ],
      ),
    );
  }
}

/// A daily trip: when to leave for its next departures and when it arrives, from the departures of its lines; the
/// last metro of the night announced an hour ahead
class DailyTripCard extends ConsumerStatefulWidget {
  const DailyTripCard({super.key, required this.trip});

  final DailyTrip trip;

  @override
  ConsumerState<DailyTripCard> createState() => _DailyTripCardState();
}

class _DailyTripCardState extends ConsumerState<DailyTripCard> {
  late bool _reversed = startsReversed(widget.trip, ref.read(favoritesProvider).value ?? const [], DateTime.now());

  late DailyTrip _back = widget.trip.reversed();

  @override
  void didUpdateWidget(DailyTripCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip != widget.trip) {
      _back = widget.trip.reversed();
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(dailyTripsProvider.notifier).remove(widget.trip);
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.dailyTripRemoved)));
  }

  @override
  Widget build(BuildContext context) {
    final trip = _reversed ? _back : widget.trip;
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final options = upcomingTrips(trip.journey, lookup: watchRides(ref, now), now: now);
    final next = options.first;
    final alert = lastTripText(lastTripAlert(trip.journey, watchSpans(ref), now), now);
    final theme = Theme.of(context);
    final colors = context.colors;
    final leaveIn = next.departure.difference(now);
    final live = next.rides.firstOrNull?.realtime == true;
    final startName = tripPlaceName(trip.start, favorites);
    final endName = tripPlaceName(trip.end, favorites);
    final name = context.l10n.dailyTripName(startName, endName);
    final icon = endName == context.l10n.home
        ? Icons.home_rounded
        : endName == context.l10n.work
        ? Icons.work_rounded
        : Icons.route;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 14),
      onTap: () {
        ref.read(selectedJourneyProvider.notifier).select(next, trip.request);
        context.push(Routes.journeyDetailOf(trip.request, next));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBubble(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
              IconButton(
                tooltip: context.l10n.dailyTripReverse,
                icon: Icon(Icons.swap_horiz, color: colors.muted),
                onPressed: () => setState(() => _reversed = !_reversed),
              ),
              PopupMenuButton<void>(
                tooltip: context.l10n.dailyTripMenu,
                icon: Icon(Icons.more_vert, color: colors.muted),
                itemBuilder: (context) => [
                  PopupMenuItem(onTap: _remove, child: Text(context.l10n.dailyTripRemove)),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leaveIn.inMinutes <= 0 ? context.l10n.leaveNowShort : context.l10n.leaveIn(formatDuration(leaveIn.inSeconds)),
                        style: theme.textTheme.titleMedium?.copyWith(color: live ? colors.live : null),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '${formatClock(next.departure)} → ${formatClock(next.arrival)}',
                          if (options.length > 1)
                            context.l10n.dailyTripThen(options.skip(1).map((option) => formatClock(option.departure)).join(', ')),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatDuration(next.duration), style: theme.textTheme.titleLarge),
                const SizedBox(width: 10),
                // Straight to GO on the next departure: the usual gesture for a daily trip
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(56, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () {
                    ref.read(goControllerProvider.notifier).start(next, trip.request);
                    context.push(Routes.go);
                  },
                  child: Text(context.l10n.go),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 10, right: 12), child: SectionsStrip(journey: next)),
          if (alert != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 12),
              child: NoticeLine(icon: Icons.nightlight_round, text: alert),
            ),
        ],
      ),
    );
  }
}

/// Saves the journey shown as a daily trip, or takes it out of them
class SaveDailyTripButton extends ConsumerWidget {
  const SaveDailyTripButton({super.key, required this.journey, required this.request});

  final JourneyOption journey;
  final JourneyRequest? request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dailyTripsProvider);
    final trips = ref.read(dailyTripsProvider.notifier);
    final saved = trips.find(journey);
    // Without public transport there is nothing to follow
    if (journey.rides.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: saved == null ? context.l10n.dailyTripSave : context.l10n.dailyTripRemove,
      icon: Icon(saved == null ? Icons.bookmark_add_outlined : Icons.bookmark_added),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (saved == null) {
          await trips.save(journey, request ?? const JourneyRequest());
          messenger.showSnackBar(SnackBar(content: Text(currentL10n.dailyTripSaved)));
        } else {
          await trips.remove(saved);
          messenger.showSnackBar(SnackBar(content: Text(currentL10n.dailyTripRemoved)));
        }
      },
    );
  }
}

/// On a ride of a journey: its line's last departure of the night when the ride is among the last ones
class LastRideTag extends ConsumerWidget {
  const LastRideTag({super.key, required this.ride});

  final JourneySection ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final span = watchSpans(ref)(ride);
    final last = span?.last;
    final line = ride.line;
    if (last == null || line == null) {
      return const SizedBox.shrink();
    }
    final next = span!.next;
    final allNight = next != null && next.departure.difference(last.departure) < const Duration(hours: 1);
    // Taken within the half hour before the last one
    if (allNight || last.departure.difference(ride.departure) > const Duration(minutes: 30) ||
        last.departure.isBefore(ride.departure.subtract(const Duration(minutes: 1)))) {
      return const SizedBox.shrink();
    }
    return PillTag(
      icon: Icons.nightlight_round,
      text: context.l10n.lastRideOf(modeNoun(line.mode), line.name ?? '', formatClock(last.departure)),
      color: context.colors.warning,
    );
  }
}
