import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../traffic/traffic_providers.dart';
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
/// The saved trip to [place]: one ending there, else the way back of one starting there; null without
DailyTrip? tripTo(List<DailyTrip> trips, Favorite place) {
  final lat = place.lat;
  final lon = place.lon;
  if (lat == null || lon == null) {
    return null;
  }
  bool near(JourneyPoint? point) => point != null && metersBetween(LatLng(point.lat, point.lon), LatLng(lat, lon)) < 200;
  for (final trip in trips) {
    if (near(trip.end) && !near(trip.start)) {
      return trip;
    }
  }
  for (final trip in trips) {
    if (near(trip.start) && !near(trip.end)) {
      return trip.reversed();
    }
  }
  return null;
}

/// The next departure of the saved trip to [place] (see [tripTo]), retimed on its lines' departures (no search); null
/// without such a trip, or when the user is there already
JourneyOption? nextTripTo(WidgetRef ref, Favorite place, DateTime now) {
  final trip = tripTo(ref.watch(dailyTripsProvider).value ?? const [], place);
  final user = ref.watch(userLocationProvider).value;
  if (trip == null ||
      (user != null && place.lat != null && metersBetween(user, LatLng(place.lat!, place.lon!)) < 300)) {
    return null;
  }
  return upcomingTrips(trip.journey, lookup: watchRides(ref, now), now: now).firstOrNull;
}

/// Goes to [place]: the detail of the next departure of the trip saved there (no search), else a search from here
void goToPlace(BuildContext context, WidgetRef ref, Favorite place) {
  final now = ref.read(nowProvider).value ?? DateTime.now();
  final trip = tripTo(ref.read(dailyTripsProvider).value ?? const [], place);
  final next = trip == null ? null : nextTripTo(ref, place, now);
  if (trip != null && next != null) {
    ref.read(selectedJourneyProvider.notifier).select(next, trip.request);
    context.push(Routes.journeyDetailOf(trip.request, next));
    return;
  }
  context.push(Routes.journey(ref.read(journeyPreferencesProvider).apply(JourneyRequest(
        from: const JourneyPlace.currentLocation(),
        to: favoritePlace(place),
      ))));
}

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
  const DailyTripsSection({super.key, this.except});

  /// Shown above already, as the commute card
  final String? except;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(dailyTripsProvider).value ?? const <DailyTrip>[];
    final trips = [for (final trip in all) if (trip.id != except) trip];
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    final home = favorites.where((favorite) => favorite.kind == FavoriteKind.home).firstOrNull;
    final work = favorites.where((favorite) => favorite.kind == FavoriteKind.work).firstOrNull;
    final names = [for (final trip in all) {tripPlaceName(trip.start, favorites), tripPlaceName(trip.end, favorites)}];
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

/// A daily trip: when to leave for its next departures (large, green) and when it arrives, from the departures of its
/// lines, GO in one tap, its lines, then what threatens it: a disrupted line, the last metro of the night (an hour
/// ahead it becomes the main information: "Partez avant 00:33")
class DailyTripCard extends ConsumerStatefulWidget {
  const DailyTripCard({super.key, required this.trip, this.heading});

  /// As given when [heading] is set (already the way to the suggested place), else turned by [startsReversed]
  final DailyTrip trip;

  /// The home page's suggestion this card answers ("Aller au travail" and its icon), instead of the trip's name
  final ({IconData icon, String title})? heading;

  @override
  ConsumerState<DailyTripCard> createState() => _DailyTripCardState();
}

class _DailyTripCardState extends ConsumerState<DailyTripCard> {
  late bool _reversed =
      widget.heading == null && startsReversed(widget.trip, ref.read(favoritesProvider).value ?? const [], DateTime.now());

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
    final last = lastTripAlert(trip.journey, watchSpans(ref), now);
    // The last ride close: when to leave at the latest is what matters now
    final leaveBy = last?.leaveBy;
    final night = leaveBy != null && leaveBy.difference(now) <= lastRideWarning;
    final alert = night ? null : lastTripText(last, now);
    final theme = Theme.of(context);
    final colors = context.colors;
    final leaveIn = next.departure.difference(now);
    final startName = tripPlaceName(trip.start, favorites);
    final endName = tripPlaceName(trip.end, favorites);
    final name = context.l10n.dailyTripName(startName, endName);
    final icon = endName == context.l10n.home
        ? Icons.home_rounded
        : endName == context.l10n.work
        ? Icons.work_rounded
        : Icons.route;
    // A disrupted line of the trip, with what happens on it
    final traffic = {for (final line in ref.watch(trafficProvider).value ?? const <LineTraffic>[]) line.line.id: line};
    final disrupted = next.rides
        .map((ride) => traffic[ride.line?.id])
        .where((line) => line?.severity != null && line!.severity != DisruptionSeverity.info)
        .firstOrNull;
    final large = theme.textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1.2);
    final heading = widget.heading;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 14),
      onTap: () {
        ref.read(selectedJourneyProvider.notifier).select(next, trip.request);
        context.push(Routes.journeyDetailOf(trip.request, next));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (heading != null)
                Icon(heading.icon, size: 18, color: heading.icon == Icons.work_rounded ? theme.colorScheme.secondary : theme.colorScheme.primary)
              else
                IconBubble(icon, color: theme.colorScheme.primary, size: 28),
              SizedBox(width: heading != null ? 8 : 10),
              Expanded(
                child: Text(heading?.title ?? name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 14)),
              ),
              IconButton(
                tooltip: context.l10n.dailyTripReverse,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.swap_horiz, size: 20, color: colors.muted),
                onPressed: () => setState(() => _reversed = !_reversed),
              ),
              PopupMenuButton<void>(
                tooltip: context.l10n.dailyTripMenu,
                icon: Icon(Icons.more_vert, size: 20, color: colors.muted),
                itemBuilder: (context) => [
                  PopupMenuItem(onTap: _remove, child: Text(context.l10n.dailyTripRemove)),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (night)
                        Row(
                          children: [
                            Icon(Icons.nightlight_round, size: 20, color: colors.warning),
                            const SizedBox(width: 6),
                            Flexible(child: Text(context.l10n.leaveBefore(formatClock(leaveBy)), style: large?.copyWith(color: colors.warning))),
                          ],
                        )
                      else
                        Text(
                          switch (leaveIn.inMinutes) {
                            <= 0 => context.l10n.leaveNowShort,
                            final minutes when minutes < 60 => context.l10n.leaveInMinutes(minutes),
                            _ => leaveInLabel(leaveIn),
                          },
                          style: large?.copyWith(color: colors.live),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        night
                            ? [
                                context.l10n.goArrivesIn(formatDuration(leaveBy.difference(now).inSeconds)),
                                if (last!.ride.line case final line? when last.lastDeparture != null)
                                  context.l10n.lastRideOf(modeNoun(line.mode), line.name ?? '', formatClock(last.lastDeparture!)),
                              ].join(' · ')
                            : [
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
                // At night, when to leave takes the room
                if (night)
                  const SizedBox.shrink()
                else if (next.duration < 3600)
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${(next.duration / 60).round()}', style: large),
                    TextSpan(text: '\u00a0min', style: theme.textTheme.labelMedium),
                  ]))
                else
                  Text(formatDuration(next.duration), style: large),
                const SizedBox(width: 12),
                // Straight to GO on the next departure: the usual gesture for a daily trip
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(60, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref.read(goControllerProvider.notifier).start(next, trip.request);
                    context.push(Routes.go);
                  },
                  child: Text(context.l10n.go),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 10, right: 12), child: SectionsStrip(journey: next)),
          if (disrupted != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 12),
              child: NoticeLine(
                icon: disrupted.severity == DisruptionSeverity.blocking ? Icons.block : Icons.warning_rounded,
                color: disrupted.severity == DisruptionSeverity.blocking ? colors.cancelled : colors.warning,
                text: switch (disrupted.titles.firstOrNull) {
                  // Titles often name the line already
                  final title? when title.contains(disrupted.line.label) => title,
                  final title => context.l10n.lineTrafficNotice(
                      disrupted.line.label,
                      title ?? (disrupted.severity == DisruptionSeverity.blocking ? context.l10n.trafficInterrupted : context.l10n.trafficDisrupted),
                    ),
                },
              ),
            ),
          if (alert != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 12),
              child: NoticeLine(icon: last?.over == true ? Icons.bedtime_outlined : Icons.nightlight_round, text: alert),
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
