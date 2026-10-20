import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/share.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../go/go_controller.dart';
import 'journey_labels.dart';
import 'journey_providers.dart';
import 'journey_request.dart';
import 'journey_retime.dart';
import 'widgets/journey_card.dart';
import 'widgets/journey_map.dart';
import 'widgets/journey_sections.dart';
import 'widgets/journey_timeline.dart';

/// Step by step view of a journey option. Each ride lists its departures; choosing another one moves the journey
/// to it, the following connections included (see [retimeJourney]).
class JourneyDetailScreen extends ConsumerStatefulWidget {
  const JourneyDetailScreen({super.key, this.query = ''});

  /// Search, departure time and lines of the option (`Routes.journeyDetailOf`): the option is found again from them
  /// when it is not in memory (web reload, shared link)
  final String query;

  @override
  ConsumerState<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends ConsumerState<JourneyDetailScreen> {
  /// Departures chosen by section index, for [_choicesOf]
  Map<int, Ride> _choices = const {};
  JourneyOption? _choicesOf;

  /// Ride whose stops are shown in the timeline, framed on the map; null: the whole journey
  int? _focused;

  void _focus(int index, bool focus) => setState(() => _focused = focus ? index : (_focused == index ? null : _focused));

  void _choose(int index, Ride ride) => setState(() {
    // The following rides go back to the first departure they can catch
    _choices = {
      for (final entry in _choices.entries)
        if (entry.key < index) entry.key: entry.value,
      index: ride,
    };
  });

  @override
  Widget build(BuildContext context) {
    final params = Uri.splitQueryString(widget.query);
    final departure = DateTime.tryParse(params['dep'] ?? '');
    final selected = ref.watch(selectedJourneyProvider);
    // The option in memory when it is the one of the URL
    final inMemory = selected != null && (departure == null || selected.departure.isAtSameMomentAs(departure));
    final shared = inMemory || departure == null ? null : ref.watch(sharedJourneyProvider(widget.query));
    final planned = inMemory ? selected : shared?.value;
    final request = inMemory ? ref.read(selectedJourneyProvider.notifier).request : JourneyRequest.fromQuery(params);

    void back() =>
        context.canPop() ? context.pop() : context.go(request == null ? Routes.home : Routes.journey(request));

    if (planned == null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
          ),
          if (shared != null && shared.isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(context.l10n.journeyNotFound, textAlign: TextAlign.center),
                  if (request != null && request.isComplete)
                    TextButton(
                      onPressed: () => context.go(Routes.journey(request.copyWith(datetime: () => null))),
                      child: Text(context.l10n.searchAgain),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    if (_choicesOf != planned) {
      _choicesOf = planned;
      _choices = const {};
      _focused = null;
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final retimed = retimeJourney(planned, lookup: watchRides(ref, now), now: now, choices: _choices);
    final journey = retimed.journey;

    return MapOverlayScope(
      overlay: journeyOverlay(context, journey, fitSection: _focused),
      // Citymapper's big green GO stays at hand at the bottom, whatever is scrolled
      child: Column(
        children: [
          Expanded(child: _content(context, journey, retimed, planned, request, back)),
          _GoFooter(
            journey: journey,
            now: now,
            onGo: () {
              ref.read(goControllerProvider.notifier).start(journey, request);
              context.push(Routes.go);
            },
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, JourneyOption journey, RetimedJourney retimed, JourneyOption planned, JourneyRequest? request,
      VoidCallback back) {
    final theme = Theme.of(context);
    return ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 32),
        children: [
          Row(
            children: [
              IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
              const Spacer(),
              SaveDailyTripButton(journey: planned, request: request),
              IconButton(
                tooltip: context.l10n.share,
                icon: const Icon(Icons.ios_share),
                onPressed: () => shareLink(
                  context,
                  title: context.l10n.journeyShareTitle(
                    journey.sections.firstOrNull?.from?.name ?? '',
                    journey.sections.lastOrNull?.to?.name ?? '',
                  ),
                  location: Routes.journeyDetailOf((request ?? const JourneyRequest()).forSharing(planned), planned),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDuration(journey.duration), style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28)),
                      Text(
                        [
                          '${formatClock(journey.departure)} → ${formatClock(journey.arrival)}',
                          journeyTypeLabel(journey.type),
                          if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
                          if (journey.co2 != null) context.l10n.co2(journey.co2!.round()),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 16),
            child: SectionsStrip(journey: journey),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in journey.sections.indexed)
                  JourneySectionTile(
                    section: section,
                    isFirst: index == 0,
                    ride: retimed.rides[index],
                    onChoose: (ride) => _choose(index, ride),
                    focused: _focused == index,
                    onFocus: (focus) => _focus(index, focus),
                  ),
                if (journey.sections.lastOrNull?.to case final end?)
                  TimelineRow(
                    color: theme.colorScheme.error,
                    time: formatClock(journey.arrival),
                    dot: true,
                    isLast: true,
                    child: Text(end.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
    );
  }
}

/// At the bottom of the detail: when to leave, the duration and arrival, the big green GO
class _GoFooter extends StatelessWidget {
  const _GoFooter({required this.journey, required this.now, required this.onGo});

  final JourneyOption journey;
  final DateTime now;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leaveIn = journey.departure.difference(now);
    final live = journey.rides.firstOrNull?.realtime == true;
    return Material(
      color: context.colors.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      leaveInLabel(leaveIn),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: live ? context.colors.live : null),
                    ),
                    Text(
                      '${formatDuration(journey.duration)} · ${context.l10n.arrivalAt(formatClock(journey.arrival))}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // The theme makes filled buttons full width
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(112, 52),
                  textStyle: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1),
                ),
                icon: const Icon(Icons.navigation),
                label: Text(context.l10n.go),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onGo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
