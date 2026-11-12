import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/utils/geo.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_screen.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/go/widgets/go_departures_card.dart';
import 'package:website_app/features/go/widgets/go_exit_card.dart';
import 'package:website_app/features/go/widgets/go_ride_card.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// A journey followed in GO mode at its different moments: the controller is replaced by one holding the state (no
/// GPS in tests), the screens are the app's
class _FollowedJourney extends GoController {
  _FollowedJourney(this.initial);

  final GoState initial;

  @override
  GoState? build() => initial;
}

void main() {
  final now = DateTime.now().toUtc();
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));

  // Walk 4 min to Châtelet (two turns), metro 1 in 6 min to Nation through Gare de Lyon, walk 3 min: its cards are the
  // walk, the metro's departures, the metro, getting out at Nation, the walk, the arrival
  final plan = journey([
    walk(inMinutes(0), 240).copyWith(length: 500, steps: const [
      WalkStep(instruction: "Marchez vers l'est sur Rue de Rivoli", length: 300, offset: 0),
      WalkStep(instruction: 'Tournez à gauche sur Rue des Halles', length: 200, offset: 300, direction: -90, name: 'Rue des Halles'),
    ]),
    transit(inMinutes(6), 480, via: [gareDeLyon]).copyWith(boardingPositions: ['front']),
    walk(inMinutes(14), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
  ]);
  final tracker = GoTracker(plan);

  GoState followed(GoProgress progress, {LatLng? position}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: progress.copyWith(lastFixAt: DateTime.now()),
        startedAt: now,
        plannedArrival: plan.arrival,
        position: position,
      );

  Future<ProviderContainer> openGo(WidgetTester tester, GoState state, {FakeBackend? backend}) async {
    await pumpApp(tester, backend ?? standardBackend(), overrides: [
      goControllerProvider.overrideWith(() => _FollowedJourney(state)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
    ]);
    // The bar over the map opens GO
    await tapOn(tester, find.text(currentL10n.go).first);
    expect(find.byType(GoScreen), findsOneWidget);
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> swipe(WidgetTester tester, {int cards = 1, bool back = false}) async {
    for (var card = 0; card < cards; card++) {
      await tester.drag(find.byType(PageView), Offset(back ? 300 : -300, 0));
      await settle(tester);
    }
  }

  testWidgets('walking: where to and how long, the time to spare, the next turn first and named on the map', (tester) async {
    final along = tracker.steps.first.line.length * 260 / 500;
    final container =
        await openGo(tester, followed(GoProgress(step: 0, phase: GoPhase.moving, along: along), position: LatLng(chatelet.lat, chatelet.lon)));

    // Like Citymapper: the controls over the map, no banner; the card says where to
    expect(find.byTooltip(currentL10n.goStop), findsOneWidget);
    expect(find.byTooltip(currentL10n.goMute), findsOneWidget);
    expect(find.byTooltip(currentL10n.goKeepScreenOn), findsOneWidget);
    expect(find.text(currentL10n.goCorrect), findsNothing);
    expect(find.text(currentL10n.goVerbTo(currentL10n.goVerbWalk, 'Châtelet')), findsOneWidget);
    expect(find.textContaining("d'avance sur le Métro 1 de"), findsOneWidget);
    // The turns from the next one: the start of the walk is behind
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsOneWidget);
    expect(find.text("Marchez vers l'est sur Rue de Rivoli"), findsNothing);
    expect(find.text(currentL10n.goNoGps), findsNothing);
    // The next turn named on the map, where it is
    final overlay = container.read(mapOverlaysProvider)[Routes.go]!;
    expect(overlay.pins.map((pin) => pin.label), contains('${currentL10n.goTurnLeft} · Rue des Halles'));
    expect(overlay.follow, isNotNull);

    await closeApp(tester);
  });

  testWidgets('walking too slowly for the metro: the card says to hurry, not the turn (listed under it, named on the map)',
      (tester) async {
    // The metro in 4 min, a little more than 3 min of walk left, the turn 20 m ahead
    final along = tracker.steps.first.line.length * 280 / 500;
    await openGo(tester,
        followed(GoProgress(step: 0, phase: GoPhase.moving, along: along, shift: const Duration(minutes: -2)), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.text(currentL10n.goMarginHurry), findsOneWidget);
    expect(find.text(currentL10n.goTurnLeft), findsNothing);
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('large text (×1.8): the controls and each card hold', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openGo(tester, followed(const GoProgress(step: 0, phase: GoPhase.moving, along: 40), position: LatLng(chatelet.lat, chatelet.lon)));

    // Every card, swiped to, without any overflow (reported as errors)
    await swipe(tester, cards: 5);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 5);
    expect(find.byTooltip(currentL10n.goStop), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('"Je suis ici" on another card: GO goes on from there', (tester) async {
    final container =
        await openGo(tester, followed(const GoProgress(step: 0, phase: GoPhase.moving), position: LatLng(chatelet.lat, chatelet.lon)));
    expect(find.text(currentL10n.goImHere), findsNothing);

    // The metro's departures: already on the platform
    await swipe(tester);
    await tapOn(tester, find.text(currentL10n.goImHere));
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.waiting);
    expect(container.read(goControllerProvider)!.progress.step, 1);

    // The metro's card: already on board
    await swipe(tester);
    await tapOn(tester, find.text(currentL10n.goImHere));
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.onBoard);

    // Up to the arrival, which offers "Je suis arrivé"
    await swipe(tester, cards: 3);
    expect(find.text(currentL10n.goImArrived), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('waiting: the departure followed in the header, the departures to choose, where to board', (tester) async {
    final container =
        await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon)));

    // Its time and punctuality from the line's departures in the card (real time), the minutes left
    final card = find.byType(GoDeparturesCard);
    expect(find.descendant(of: card, matching: find.textContaining(currentL10n.goOnTime, findRichText: true)), findsOneWidget);
    expect(find.text(currentL10n.minutesUnit), findsWidgets);
    expect(find.text(currentL10n.direction('Nation')), findsOneWidget);
    // Where to board along the train, the departures and the next one if missed
    expect(find.byType(TrainPositions), findsOneWidget);
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsOneWidget);
    // The map frames the stop where to board, the user there, not the whole ride
    expect(container.read(mapOverlaysProvider)[Routes.go]!.fit, [LatLng(chatelet.lat, chatelet.lon), LatLng(chatelet.lat, chatelet.lon)]);

    await closeApp(tester);
  });

  testWidgets("waiting for a late vehicle: its planned time struck through, the new one beside it, no minutes to add",
      (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          ride(inMinutes(9), aimed: inMinutes(6)).toJson(),
          ride(inMinutes(12)).toJson(),
        ]));
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon)),
        backend: backend);

    final header = find.descendant(
      of: find.byType(GoDeparturesCard),
      matching: find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText().contains(formatClock(inMinutes(6)))),
    );
    final spans = <TextSpan>[];
    tester.widget<RichText>(header.first).text.visitChildren((span) {
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
        spans.add(span);
      }
      return true;
    });
    expect([for (final span in spans) span.text!.trim()], [formatClock(inMinutes(6)), formatClock(inMinutes(9))]);
    expect(spans.first.style?.decoration, TextDecoration.lineThrough);
    expect(find.textContaining(currentL10n.goMinutesLate(3), findRichText: true), findsNothing);

    await closeApp(tester);
  });

  testWidgets('on board: the stops left on a rail, the next one, where to get off, its alerts switched off', (tester) async {
    final container = await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 0)));

    expect(find.text(currentL10n.goStopsTo(2, 'Nation')), findsOneWidget);
    expect(find.text(currentL10n.goNextStop('Gare de Lyon')), findsOneWidget);
    expect(find.text(currentL10n.goNextStopLabel), findsOneWidget);
    expect(find.text(currentL10n.goGetOffHere), findsOneWidget);

    // "Alerter quand descendre", on until switched off
    expect(container.read(goControllerProvider)!.alightAlertsOff, isEmpty);
    await tapOn(tester, find.text(currentL10n.goAlightAlert));
    expect(container.read(goControllerProvider)!.alightAlertsOff, {1});

    await closeApp(tester);
  });

  testWidgets('getting off in a minute: the ride card says it in red', (tester) async {
    // Gare de Lyon left, Nation in a minute
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 1, shift: Duration(minutes: -13))));

    expect(find.text(currentL10n.goGetOffNext), findsOneWidget);
    final header = tester.widget<AnimatedContainer>(find.ancestor(of: find.text(currentL10n.goGetOffNext), matching: find.byType(AnimatedContainer)).first);
    expect((header.decoration as BoxDecoration?)?.color, isNotNull);

    await closeApp(tester);
  });

  testWidgets('getting out at Nation: the best way out, every way out on the map', (tester) async {
    final backend = standardBackend();
    backend.get('/api/v2/stops/IDFM:70003', const StopAreaDetail(
      id: 'IDFM:70003',
      name: 'Nation',
      lat: 48.8484,
      lon: 2.3959,
      entrances: [
        StationEntrance(id: 'E2', code: '2', name: 'av. du Trône', lat: 48.84777, lon: 2.39683),
        StationEntrance(id: 'E6', code: '6', name: 'av. du Bel Air', lat: 48.84750, lon: 2.39589),
      ],
    ).toJson());
    final container = await openGo(tester, followed(const GoProgress(step: 2, phase: GoPhase.moving)), backend: backend);

    final card = find.byType(GoExitCard);
    expect(find.descendant(of: card, matching: find.text(currentL10n.goExitStation)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(currentL10n.goBestExit)), findsOneWidget);
    // The one on the walk's way, not the one behind
    expect(find.descendant(of: card, matching: find.text(currentL10n.goExitNamed('2', 'av. du Trône'))), findsOneWidget);
    final pins = container.read(mapOverlaysProvider)[Routes.go]!.pins.map((pin) => pin.label);
    expect(pins, containsAll([currentL10n.goExitNamed('2', 'av. du Trône'), currentL10n.goExitNamed('6', 'av. du Bel Air')]));

    // Then the walk, as long as its path (Navitia's length sometimes leaves out the way through the station)
    await swipe(tester);
    final walk = tracker.steps[2];
    expect(walk.line.length, greaterThan(walk.section.length!));
    expect(find.text(formatDistance(walk.line.length.round())), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('missed: the departures card says it, the next departure in one tap', (tester) async {
    await openGo(tester,
        followed(const GoProgress(step: 1, phase: GoPhase.waiting, issue: GoIssue.missed), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.text(currentL10n.goMissedChoose('Métro 1')), findsOneWidget);
    expect(find.text(currentL10n.goTakeThisOne), findsOneWidget);
    expect(find.text(currentL10n.recalculate), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the latest alert: in the cards on the GO page (no strip over the map), in the bar on the other pages', (tester) async {
    const alert = GoAlert(id: 'soon-1', title: 'Métro 1 dans 2 min', body: 'Direction Nation');
    final state = followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon))
        .copyWith(alert: alert, alertAt: DateTime.now());

    await openGo(tester, state);
    expect(find.text('Métro 1 dans 2 min · Direction Nation'), findsNothing);
    expect(find.text('Métro 1 dans 2 min'), findsNothing);

    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(find.byType(GoScreen), findsNothing);
    expect(find.text('Métro 1 dans 2 min'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('looking at the other cards leaves the sheet where it is: it fits the card going on', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 0, phase: GoPhase.moving, along: 40), position: LatLng(chatelet.lat, chatelet.lon)));
    double sheetTop() => tester
        .getTopLeft(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Material)).first)
        .dy;
    final top = sheetTop();
    // The map keeps at least half of the screen
    expect(top, greaterThanOrEqualTo(915 * 0.5 - 1));

    // Each card up to the arrival's: swiped to, the sheet stays
    for (var card = 0; card < 5; card++) {
      await swipe(tester);
      expect(sheetTop(), closeTo(top, 1));
    }
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 5);
    // Back to the card going on
    await swipe(tester, cards: 5, back: true);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(sheetTop(), closeTo(top, 1));

    await closeApp(tester);
  });

  testWidgets('waiting: GO and its departures card ask the departures once, for both', (tester) async {
    // A device whose GPS gives nothing yet: GO starts from the app's position
    final messenger = tester.binding.defaultBinaryMessenger;
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    messenger.setMockStreamHandler(updates, MockStreamHandler.inline(onListen: (_, _) {}));
    messenger.setMockMethodCallHandler(geolocator, (_) async => null);
    addTearDown(() {
      messenger.setMockStreamHandler(updates, null);
      messenger.setMockMethodCallHandler(geolocator, null);
    });
    final backend = standardBackend();
    await pumpApp(tester, backend, overrides: [liveJourneyProvider.overrideWithValue(_NoLiveJourney())]);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(goControllerProvider.notifier)
      ..start(plan, const JourneyRequest())
      ..jumpTo(1);
    await settle(tester);
    await tapOn(tester, find.text(currentL10n.go).first);
    expect(find.byType(GoScreen), findsOneWidget);

    // The card lists them, the controller follows the planned vehicle in them
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsOneWidget);
    expect(backend.requests.where((request) => request.uri.path.endsWith('/rides')), hasLength(1));
    // With real time: a vehicle gone from them has left (the tracker gives it up sooner than one only scheduled)
    expect(container.read(goControllerProvider)?.realtimeDepartures, isTrue);

    await closeApp(tester);
  });

  testWidgets('arrived: the summary, the way back', (tester) async {
    await openGo(tester, followed(GoProgress(step: 3, phase: GoPhase.arrived, arrivedAt: inMinutes(17))));

    expect(find.text(currentL10n.goArrived), findsWidgets);
    expect(find.text(currentL10n.goWayBack), findsOneWidget);
    expect(find.text(currentL10n.goFinished), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('missed at the stop: the next departure is kept on its own and said in the departures card', (tester) async {
    // The RER left 2 min ago; the user is still on the platform
    final missedPlan = journey([
      walk(inMinutes(-6), 240),
      transit(inMinutes(-2), 480, line: rerA, via: [gareDeLyon]),
    ]);
    final messenger = tester.binding.defaultBinaryMessenger;
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final fix = {
      'latitude': chatelet.lat,
      'longitude': chatelet.lon,
      'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'accuracy': 5.0,
      'altitude': 0.0,
      'altitude_accuracy': 0.0,
      'heading': 0.0,
      'heading_accuracy': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'is_mocked': false,
    };
    messenger.setMockStreamHandler(updates, MockStreamHandler.inline(onListen: (_, sink) => sink.success(fix)));
    messenger.setMockMethodCallHandler(geolocator, (_) async => null);
    addTearDown(() {
      messenger.setMockStreamHandler(updates, null);
      messenger.setMockMethodCallHandler(geolocator, null);
    });
    final backend = standardBackend();
    // The next train, in 7 min, is an express straight to Nation
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          ride(inMinutes(7)).copyWith(stops: [
            JourneyStop(name: 'Châtelet', lat: chatelet.lat, lon: chatelet.lon, time: inMinutes(7)),
            JourneyStop(name: 'Nation', lat: nation.lat, lon: nation.lon, time: inMinutes(15)),
          ]).toJson(),
          for (final minutes in [12, 17]) ride(inMinutes(minutes)).toJson(),
        ]));
    await pumpApp(tester, backend, overrides: [liveJourneyProvider.overrideWithValue(_NoLiveJourney())]);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(goControllerProvider.notifier).start(missedPlan, const JourneyRequest());
    // The first fix, GO open, then the user says they are at the stop
    await settle(tester, const Duration(seconds: 1));
    await tapOn(tester, find.text(currentL10n.go).first);
    container.read(goControllerProvider.notifier).jumpTo(1);
    await settle(tester, const Duration(seconds: 8));

    final state = container.read(goControllerProvider)!;
    // The next train (in 7 min) is now the plan, without a tap, where it stops too
    expect(state.retained, isNotNull);
    expect(state.progress.issue, isNull);
    expect(state.journey.rides.single.departure.isAfter(DateTime.now().toUtc()), isTrue);
    expect(state.journey.rides.single.stops.map((stop) => stop.name), ['Châtelet', 'Nation']);
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);
    expect(find.text(currentL10n.goMissedShort('RER A')), findsOneWidget);
    expect(find.text(currentL10n.goRecalculateJourney), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('on board, the map fades the ride up to where the GPS saw the user, not where the clock puts them', (tester) async {
    // The metro 1 left Châtelet 3 min ago for Gare de Lyon (4 min) and Nation: three quarters of the way by the clock
    final start = DateTime.now().toUtc();
    final onBoard = journey([transit(start.subtract(const Duration(minutes: 3)), 480, via: [gareDeLyon])]);
    Future<List<MapPath>> ridePaths(double along) async {
      final container = await openGo(
        tester,
        GoState(
          tracker: GoTracker(onBoard),
          request: const JourneyRequest(),
          progress: GoProgress(step: 0, phase: GoPhase.onBoard, along: along, lastFixAt: start),
          startedAt: start,
          plannedArrival: onBoard.arrival,
        ),
      );
      final paths = container.read(mapOverlaysProvider)[Routes.go]!.paths;
      await closeApp(tester);
      return paths;
    }

    // Underground since Châtelet, the user's dot still there: nothing faded ahead of it
    final unseen = await ridePaths(0);
    expect(unseen, hasLength(1));
    expect(unseen.single.color.a, 1);

    // Seen 300 m along the ride: faded up to there
    final seen = await ridePaths(300);
    expect(seen, hasLength(2));
    expect(seen.first.color.a, lessThan(1));
    expect(MeasuredPolyline(seen.first.points).length, closeTo(300, 1));
    expect(seen.last.color.a, 1);
  });

  testWidgets("on board, the user is on the ride's rail where the clock puts them between two stops, not halfway", (tester) async {
    /// Where the user's dot is on the rail, as a share of the way from the stop left to the next one, the metro 1
    /// having left Châtelet [minutes] ago for Gare de Lyon (4 min) and Nation (4 min more), underground
    Future<double> shown(int minutes) async {
      final start = DateTime.now().toUtc();
      final onBoard = journey([transit(start.subtract(Duration(minutes: minutes)), 480, via: [gareDeLyon])]);
      await openGo(
        tester,
        GoState(
          tracker: GoTracker(onBoard),
          request: const JourneyRequest(),
          progress: const GoProgress(step: 0, phase: GoPhase.onBoard),
          startedAt: start,
          plannedArrival: onBoard.arrival,
        ),
      );
      final card = find.byType(GoRideCard);
      // The user's dot is drawn last, over the rail and the stops
      final me = tester.getCenter(find.descendant(of: card, matching: find.byType(Positioned)).last).dy;
      final left = tester.getCenter(find.descendant(of: card, matching: find.text('Châtelet'))).dy;
      final next = tester.getCenter(find.descendant(of: card, matching: find.text('Gare de Lyon'))).dy;
      await closeApp(tester);
      return (me - left) / (next - left);
    }

    expect(await shown(1), closeTo(0.25, 0.03));
    expect(await shown(3), closeTo(0.75, 0.03));
  });
}

/// No notification nor screen kept on in the tests
class _NoLiveJourney implements LiveJourney {
  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}

  @override
  void onStop(VoidCallback stop) {}

  @override
  Future<bool> stopRequested() async => false;
}
