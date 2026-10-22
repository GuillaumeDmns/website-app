import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/config.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/colors.dart';
import '../../core/widgets/size_reporter.dart';
import '../../l10n/l10n.dart';
import '../journey/widgets/journey_map.dart';
import 'go_controller.dart';
import 'go_guidance.dart';
import 'go_state.dart';
import 'go_tracker.dart';
import 'widgets/go_arrival_card.dart';
import 'widgets/go_header.dart';
import 'widgets/go_move_card.dart';
import 'widgets/go_now_card.dart';
import 'widgets/go_ride_card.dart';

/// GO mode, map first: what to do now floats over the map ([GoBanner], from [GoBar]); the panel is a low capsule with
/// the arrival, the strip of the steps (tap one to look at it) and one card per step, swiped horizontally. The card of
/// the step in progress opens on its context ([GoNowCard]: the stops ahead, where to board, one line of context, the
/// manual correction); its details (departures, stops left, turns) are a drag of the sheet away. The page follows the
/// step in progress; the map frames the step shown (on a ride, what is left of it) or follows the user on foot.
class GoScreen extends ConsumerStatefulWidget {
  const GoScreen({super.key});

  @override
  ConsumerState<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends ConsumerState<GoScreen> {
  PageController? _pages;

  /// Page shown (a step index, or `steps.length` for the arrival)
  int _shown = 0;

  /// Step in progress when the page last followed it
  int? _followed;

  /// Heights of the parts of the page, to fit the bottom sheet to the card shown
  double _top = 0;
  final _cards = <int, double>{};
  bool _newCard = true;

  void _fitSheet() {
    final card = _cards[_shown];
    if (card == null || !mounted) {
      return;
    }
    PanelSheetScope.fitContent(context, _top + card + MediaQuery.paddingOf(context).bottom, reset: _newCard);
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
    final arrived = progress.phase == GoPhase.arrived;
    final live = arrived ? tracker.steps.length : progress.step;
    final pageCount = tracker.steps.length + 1;

    // A new step in progress: show it
    if (_pages == null) {
      _shown = live;
      _followed = live;
      _pages = PageController(initialPage: live);
    } else if (_followed != live) {
      _followed = live;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(live));
    }

    return MapOverlayScope(
      overlay: _overlay(state, live),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // Clipped, never overflowing, for the frame where it grew (an issue shown) before the sheet fits it
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: SingleChildScrollView(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                child: SizeReporter(
                  onSize: (size) {
                    _top = size.height;
                    _fitSheet();
                  },
                  child: Column(
                    children: [
                      GoHeader(state: state, onBack: back),
                      if (AppConfig.isDev) const GoGpsStats(),
                      GoStepStrip(state: state, shown: _shown, onTap: _show),
                      if (progress.issue case final issue? when issue != GoIssue.offRoute) GoIssueCard(state: state, issue: issue),
                      if (progress.issue == GoIssue.offRoute) GoOffRouteBanner(state: state),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              // Swipe with a mouse or a trackpad too (desktop, web)
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: pageCount,
                  onPageChanged: (page) {
                    setState(() => _shown = page);
                    _newCard = true;
                    _fitSheet();
                  },
                  itemBuilder: (context, page) {
                    final isLive = page == live && !arrived;
                    final Widget card = page >= tracker.steps.length
                        ? GoArrivalCard(state: state)
                        : tracker.steps[page].isRide
                        ? GoRideCard(state: state, index: page, compact: isLive)
                        : GoMoveCard(state: state, index: page, compact: isLive);
                    void onSize(Size size) {
                      _cards[page] = size.height + 16;
                      if (page == _shown) {
                        _fitSheet();
                      }
                    }

                    return SingleChildScrollView(
                      // The bottom sheet is dragged by the list of the page shown only
                      controller: page == _shown ? PanelScrollScope.of(context) : null,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      // In progress, the sheet fits the context only: the map keeps most of the screen
                      child: isLive
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizeReporter(
                                  onSize: onSize,
                                  child: GoNowCard(state: state),
                                ),
                                const SizedBox(height: 16),
                                card,
                              ],
                            )
                          : SizeReporter(onSize: onSize, child: card),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The journey on the map, framing the step shown; on the ride in progress, what is left of it (from the last stop
  /// passed to where to get off), the next stop marked
  MapOverlay _overlay(GoState state, int live) {
    final tracker = state.tracker;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final shownStep = _shown < tracker.steps.length ? tracker.steps[_shown] : null;
    final onBoardOrMoving = progress.phase == GoPhase.moving || progress.phase == GoPhase.onBoard;
    final overlay = journeyOverlay(
      context,
      state.journey,
      currentSection: arrived ? state.journey.sections.length : tracker.stepOf(progress)?.sectionIndex ?? -1,
      currentAlong: onBoardOrMoving ? progress.along : 0,
      fitSection: shownStep?.sectionIndex,
    );
    final step = tracker.stepOf(progress);
    if (step != null && progress.phase == GoPhase.onBoard && _shown == live) {
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
    return overlay.withFollow(goFollow(state, _shown));
  }
}
