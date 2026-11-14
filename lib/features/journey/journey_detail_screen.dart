import 'package:material_ui/material_ui.dart';
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
import '../../core/utils/colors.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../go/go_controller.dart';
import 'journey_providers.dart';
import 'journey_request.dart';
import 'journey_retime.dart';
import 'station_accesses.dart';
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
      // A list, for the bottom sheet to move with
      return ListView(
        controller: PanelScrollScope.of(context),
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
      overlay: journeyOverlay(
        context,
        journey,
        fitSection: _focused,
        stations: journeyStationAccesses(journey, watchStationEntrances(ref, journey)),
      ),
      // Citymapper's big green GO stays at hand at the bottom, whatever is scrolled
      child: Column(
        children: [
          Expanded(child: _content(context, journey, retimed, planned, request, back, now)),
          _GoFooter(
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
      VoidCallback back, DateTime now) {
    final theme = Theme.of(context);
    return ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 24),
        children: [
          // The essentials with the back button, each said once: the duration and the arrival, then when to leave
          // (the timeline has the times), the transfers and the fare; saving and sharing
          Row(
            children: [
              IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: formatDuration(journey.duration)),
                        TextSpan(
                          text: ' · ${context.l10n.arrivalAt(formatClock(journey.arrival))}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0, color: context.colors.muted),
                        ),
                      ]),
                      style: theme.textTheme.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: leaveInLabel(journey.departure.difference(now)),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: journey.rides.firstOrNull?.realtime == true ? context.colors.live : theme.colorScheme.onSurface,
                          ),
                        ),
                        // On one line on a phone; a larger text breaks after a dot, not before
                        if (journey.transfers > 0) TextSpan(text: '\u00a0· ${context.l10n.transfersShort(journey.transfers).replaceAll(' ', '\u00a0')}'),
                        if (journey.fare != null && journey.fare! > 0) TextSpan(text: '\u00a0· ${formatFare(journey.fare!).replaceAll(' ', '\u00a0')}'),
                      ]),
                      style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 0),
                    ),
                  ],
                ),
              ),
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
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in journey.sections.indexed)
                  // A wait after a move is said on the move's line
                  if (!_waitsAfterMove(journey, index))
                    JourneySectionTile(
                      section: section,
                      isFirst: index == 0,
                      ride: retimed.rides[index],
                      waitAfter: _waitsAfterMove(journey, index + 1) ? journey.sections[index + 1].duration : null,
                      onChoose: (ride) => _choose(index, ride),
                      focused: _focused == index,
                      onFocus: (focus) => _focus(index, focus),
                    ),
                if (journey.sections.lastOrNull?.to case final end?)
                  TimelineRow(
                    color: _endColor(context, journey),
                    time: formatClock(journey.arrival),
                    dot: true,
                    isLast: true,
                    child: PlaceName(end),
                  ),
              ],
            ),
          ),
          // The transfers and the fare are in the header: only what the journey emits is left to say
          if (journey.co2 case final co2?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
              child: Text(context.l10n.co2(co2.round()), style: theme.textTheme.bodySmall),
            ),
        ],
    );
  }
}

/// Whether the section at [index] is a wait right after a walk, a transfer or another move (not a Vélib ride, whose
/// stations have their own rows): the move's line says it, `4 min à pied, 3 min d'attente`
bool _waitsAfterMove(JourneyOption journey, int index) {
  if (index <= 0 || index >= journey.sections.length || journey.sections[index].kind != SectionKind.wait) {
    return false;
  }
  final before = journey.sections[index - 1];
  return switch (before.kind) {
    SectionKind.walk || SectionKind.transfer || SectionKind.car || SectionKind.other => true,
    SectionKind.bike => !(before.from?.name.startsWith('Station Vélib') ?? false),
    SectionKind.transit || SectionKind.wait => false,
  };
}

/// The last ride's color, for where the journey ends (the walk's dark grey after it, red without any ride)
Color _endColor(BuildContext context, JourneyOption journey) {
  final last = journey.sections.lastOrNull;
  if (last?.kind == SectionKind.transit) {
    return parseHexColor(last?.line?.color, Theme.of(context).colorScheme.primary);
  }
  return Theme.of(context).colorScheme.onSurface;
}

/// At the bottom of the detail, whatever is scrolled: the big green GO, all the width
class _GoFooter extends StatelessWidget {
  const _GoFooter({required this.onGo});

  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(textStyle: theme.textTheme.titleMedium?.copyWith(fontSize: 16, letterSpacing: 0.5)),
            icon: const Icon(Icons.navigation, size: 22),
            label: Text(context.l10n.go),
            onPressed: () {
              HapticFeedback.mediumImpact();
              onGo();
            },
          ),
        ),
      ),
    );
  }
}
