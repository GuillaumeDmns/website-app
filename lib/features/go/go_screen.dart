import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/colors.dart';
import '../../core/widgets/size_reporter.dart';
import '../../l10n/l10n.dart';
import '../journey/widgets/journey_map.dart';
import '../stops/stop_screen.dart';
import 'go_cards.dart';
import 'go_controller.dart';
import 'go_guidance.dart';
import 'go_instruction.dart';
import 'go_state.dart';
import 'go_tracker.dart';
import 'widgets/go_arrival_card.dart';
import 'widgets/go_card_parts.dart';
import 'widgets/go_departures_card.dart';
import 'widgets/go_exit_card.dart';
import 'widgets/go_ride_card.dart';
import 'widgets/go_walk_card.dart';

/// GO mode like Citymapper's, map first: its controls over the map ([GoBar] shows [GoTopBar]); the panel is one card
/// per moment of the journey ([goCards]: a walk, each ride's departures then the ride, getting out of a station, the
/// arrival), swiped, dots over them. The card going on ([goCurrentCard]) carries Citymapper's blue dot and says in its
/// header what needs attention; the others offer "Je suis ici". The page follows the card going on and the sheet fits
/// what it shows at rest (looking at another card doesn't move it). The map frames the card shown, follows the user on
/// foot with the next turn named on it, shows a station's ways out.
class GoScreen extends ConsumerStatefulWidget {
  const GoScreen({super.key});

  @override
  ConsumerState<GoScreen> createState() => _GoScreenState();
}

/// The stations' ways in and out along the journey, by move step: the best way out of the one got off at before the
/// move (and all of its ways out, for the map), the best way into the one the move ends at
typedef _Stations = ({Map<int, StationAccess> exits, Map<int, List<StationEntrance>> exitsAll, Map<int, StationAccess> entrances});

class _GoScreenState extends ConsumerState<GoScreen> {
  PageController? _pages;

  /// Card shown (its index)
  int _shown = 0;

  /// Card going on when the page last followed it
  GoCard? _followed;

  /// Heights of the parts of the page, to fit the bottom sheet to the card going on
  double _top = 0;
  final _heads = <GoCard, double>{};
  bool _newCard = true;

  void _fitSheet() {
    final followed = _followed;
    final head = followed == null ? null : _heads[followed];
    if (head == null || !mounted) {
      return;
    }
    // The head as measured, in its card's frame (12 above and under it) and the page (4 above, 12 under)
    PanelSheetScope.fitContent(context, _top + head + 24 + 16 + MediaQuery.paddingOf(context).bottom, reset: _newCard);
    _newCard = false;
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _show(int page) => _pages?.animateToPage(page, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goControllerProvider);
    void back() => context.canPop() ? context.pop() : context.go(Routes.home);

    if (state == null) {
      // The session closed itself after the arrival: back home
      if (_pages != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(Routes.home);
          }
        });
      }
      return ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
          ),
          Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.goNoJourney)),
        ],
      );
    }

    final tracker = state.tracker;
    final progress = state.progress;
    final cards = goCards(tracker);
    final stations = _stations(tracker, cards);
    final current = goCurrentCard(cards, progress, exitAlong: stations.exits[progress.step]?.along);
    final live = cards[current];

    if (_pages == null) {
      _shown = current;
      _followed = live;
      _pages = PageController(initialPage: current);
    } else if (_followed != live) {
      // Another card going on: shown, the sheet fits it
      _followed = live;
      _newCard = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(current));
    }
    _shown = math.min(_shown, cards.length - 1);

    return MapOverlayScope(
      overlay: _overlay(state, cards, current, stations),
      child: Column(
        children: [
          SizeReporter(
            onSize: (size) {
              _top = size.height;
              _fitSheet();
            },
            child: Column(
              children: [
                if (AppConfig.isDev) const GoGpsStats(),
                _Dots(count: cards.length, shown: _shown, live: current, onTap: _show),
              ],
            ),
          ),
          Expanded(
            // Swipe with a mouse or a trackpad too (desktop, web)
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: PageView.builder(
                controller: _pages,
                itemCount: cards.length,
                onPageChanged: (page) => setState(() => _shown = page),
                itemBuilder: (context, page) {
                  final card = cards[page];
                  final isLive = page == current;
                  final done = page < current;
                  void onHeadSize(Size size) {
                    _heads[card] = size.height;
                    if (card == _followed) {
                      _fitSheet();
                    }
                  }

                  final Widget child = switch (card.kind) {
                    GoCardKind.walk => GoWalkCard(
                        state: state,
                        card: card,
                        live: isLive,
                        done: done,
                        onHeadSize: onHeadSize,
                        outAlong: startsWithExit(tracker, card.step) ? stations.exits[card.step]?.along ?? leaveStationMeters : 0,
                        entrance: stations.entrances[card.step]?.entrance,
                      ),
                    GoCardKind.departures => GoDeparturesCard(state: state, card: card, live: isLive, done: done, onHeadSize: onHeadSize),
                    GoCardKind.ride => GoRideCard(state: state, card: card, live: isLive, done: done, onHeadSize: onHeadSize),
                    GoCardKind.exit =>
                      GoExitCard(state: state, card: card, live: isLive, done: done, exit: stations.exits[card.step], onHeadSize: onHeadSize),
                    GoCardKind.arrival => GoArrivalCard(state: state, onHeadSize: onHeadSize),
                  };
                  return SingleChildScrollView(
                    // The bottom sheet is dragged by the list of the page shown only
                    controller: page == _shown ? PanelScrollScope.of(context) : null,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: child,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The ways in and out of the metro and train stations of the journey, from their pages (GTFS entrances)
  _Stations _stations(GoTracker tracker, List<GoCard> cards) {
    final steps = tracker.steps;
    final exits = <int, StationAccess>{};
    final exitsAll = <int, List<StationEntrance>>{};
    final entrances = <int, StationAccess>{};
    List<StationEntrance> of(String? stopAreaId) =>
        stopAreaId == null ? const [] : ref.watch(stopAreaProvider(stopAreaId)).value?.entrances ?? const [];
    for (final card in cards) {
      if (card.kind == GoCardKind.exit) {
        final all = of(steps[card.step - 1].section.to?.stopAreaId);
        exitsAll[card.step] = all;
        if (bestExit(steps[card.step].line, all) case final best?) {
          exits[card.step] = best;
        }
      } else if (card.kind == GoCardKind.walk && card.step + 1 < steps.length && steps[card.step + 1].isRide) {
        final ride = steps[card.step + 1].section;
        final mode = ride.line?.mode;
        if (mode == TransportMode.metro || (mode?.isRail ?? false)) {
          if (bestEntrance(steps[card.step].line, of(ride.from?.stopAreaId)) case final best?) {
            entrances[card.step] = best;
          }
        }
      }
    }
    return (exits: exits, exitsAll: exitsAll, entrances: entrances);
  }

  /// The journey on the map, framing the card shown: for the card going on, the stop where to board (and the user close
  /// to it) while waiting, like Citymapper; on board what is left of the ride (from the last stop passed to where to get
  /// off), the next stop marked; on foot, the user followed
  /// with the next turn named; getting out of a station, its ways out, the best one named
  MapOverlay _overlay(GoState state, List<GoCard> cards, int current, _Stations stations) {
    final tracker = state.tracker;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final shown = cards[math.min(_shown, cards.length - 1)];
    final shownStep = shown.step < tracker.steps.length ? tracker.steps[shown.step] : null;
    final onBoardOrMoving = progress.phase == GoPhase.moving || progress.phase == GoPhase.onBoard;
    final overlay = journeyOverlay(
      context,
      state.journey,
      currentSection: arrived ? state.journey.sections.length : tracker.stepOf(progress)?.sectionIndex ?? -1,
      // Faded up to where the GPS last saw the user on the way, where their dot is: never where the clock would put
      // them on board (the dot left behind in a tunnel, the faded part running ahead of it)
      currentAlong: onBoardOrMoving ? progress.along : 0,
      fitSection: shownStep?.sectionIndex,
    );
    final step = tracker.stepOf(progress);
    final isLive = _shown == current;
    if (shown.kind == GoCardKind.exit && stations.exits[shown.step] != null) {
      return _exitOverlay(overlay, tracker, shown.step, stations.exits[shown.step]!, stations.exitsAll[shown.step] ?? const []);
    }
    if (isLive && step != null && progress.phase == GoPhase.waiting) {
      return MapOverlay(pins: overlay.pins, paths: overlay.paths, fit: goWaitingFit(step, state.position));
    }
    if (isLive && step != null && progress.phase == GoPhase.onBoard) {
      final stops = step.section.stops;
      final left = [for (var k = math.min(progress.stopIndex, stops.length - 1); k < stops.length; k++) LatLng(stops[k].lat, stops[k].lon)];
      final next = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1] : null;
      final color = parseHexColor(step.section.line?.color, Theme.of(context).colorScheme.primary);
      return MapOverlay(
        pins: [
          ...overlay.pins,
          if (next != null) MapPin(point: LatLng(next.lat, next.lon), color: color, size: 18, label: next.name, above: false),
        ],
        paths: overlay.paths,
        fit: left.length >= 2 ? left : overlay.fit,
      );
    }
    if (isLive && progress.phase == GoPhase.moving) {
      final turn = _turnPin(state);
      return MapOverlay(pins: [...overlay.pins, ?turn], paths: overlay.paths, fit: overlay.fit).withFollow(goFollow(state, progress.step));
    }
    // Another ride's departures: its stop, close up
    final start = shownStep?.start;
    if (!isLive && shown.kind == GoCardKind.departures && start != null) {
      return MapOverlay(pins: overlay.pins, paths: overlay.paths, fit: [start]);
    }
    return overlay;
  }

  /// The next turn of the walk, named where it is, like Citymapper: `↰ Rue Cantin`
  MapPin? _turnPin(GoState state) {
    final step = state.tracker.stepOf(state.progress);
    if (step == null || step.isRide) {
      return null;
    }
    final maneuver = nextManeuver(step, state.progress.along);
    if (maneuver == null || maneuver.meters > maneuverAhead) {
      return null;
    }
    return MapPin(
      point: step.line.pointAt(state.progress.along + maneuver.meters),
      color: walkPathColor,
      label: [maneuver.label, ?maneuver.walk.name].join(' · '),
      above: true,
      childSize: const Size(220, 44),
      image: 'callout-${maneuver.icon.codePoint}-${maneuver.walk.name ?? maneuver.label}',
      child: _MapCallout(icon: maneuver.icon, text: maneuver.walk.name ?? maneuver.label),
    );
  }

  /// Getting out of a station: its ways out on the map, the best one named, framed with the start of the walk
  MapOverlay _exitOverlay(MapOverlay overlay, GoTracker tracker, int step, StationAccess exit, List<StationEntrance> all) {
    final walk = tracker.steps[step];
    final station = tracker.steps[step - 1].end;
    final best = LatLng(exit.entrance.lat, exit.entrance.lon);
    final name = stationAccessName(exit.entrance, exit: true);
    return MapOverlay(
      pins: [
        ...overlay.pins,
        for (final entrance in all)
          if (entrance.id != exit.entrance.id)
            MapPin(
              point: LatLng(entrance.lat, entrance.lon),
              color: walkPathColor,
              label: stationAccessName(entrance, exit: true),
              childSize: const Size(20, 20),
              image: 'station-access',
              child: const _AccessIcon(),
            ),
        MapPin(
          point: best,
          color: AppTheme.brand,
          label: name,
          above: true,
          childSize: const Size(240, 44),
          image: 'callout-${Icons.exit_to_app.codePoint}-$name',
          child: _MapCallout(icon: Icons.exit_to_app, text: name),
        ),
      ],
      paths: overlay.paths,
      fit: [?station, best, walk.line.pointAt(math.min(walk.line.length, exit.along + 60))],
    );
  }
}

/// One dot per card over them, like Citymapper's: the one shown larger, the one going on green; a tap shows it
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.shown, required this.live, required this.onTap});

  final int count;
  final int shown;
  final int live;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < count; index++)
            Semantics(
              button: true,
              selected: index == shown,
              label: context.l10n.goCardOf(index + 1, count),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onTap(index),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: index == shown ? 10 : 7,
                    height: index == shown ? 10 : 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == live ? AppTheme.brand : (index == shown ? theme.colorScheme.onSurface : theme.colorScheme.outline),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A label on the map pointing down at a place: the next turn, a station's best way out
class _MapCallout extends StatelessWidget {
  const _MapCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  /// The map stays light in dark mode too
  static const _surface = Colors.white;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: walkPathColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: walkPathColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            CustomPaint(size: const Size(10, 6), painter: _CalloutArrow(_surface)),
          ],
        ),
      );
}

class _CalloutArrow extends CustomPainter {
  _CalloutArrow(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CalloutArrow oldDelegate) => oldDelegate.color != color;
}

/// A station's other ways out on the map: a small dark square
class _AccessIcon extends StatelessWidget {
  const _AccessIcon();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: walkPathColor, borderRadius: BorderRadius.circular(4)),
        child: const Icon(Icons.exit_to_app, size: 14, color: Colors.white),
      );
}

/// How the fixes come (development builds): is the device's GPS giving one a second?
class GoGpsStats extends ConsumerWidget {
  const GoGpsStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(goFixStatsProvider);
    // Redrawn at each fix, and by the clock while none comes
    ref.watch(nowProvider);
    final interval = stats?.interval;
    final text = stats == null
        ? context.l10n.goGpsWaiting
        : context.l10n.goGpsStats(
            stats.accuracy.round(),
            interval == null ? '?' : (interval.inMilliseconds / 1000).toStringAsFixed(1),
            DateTime.now().difference(stats.at).inSeconds,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.muted)),
    );
  }
}
