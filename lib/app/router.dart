import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/map/map_overlay.dart';
import '../features/about/about_screen.dart';
import '../features/about/privacy_screen.dart';
import '../features/auth/account_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/go/go_screen.dart';
import '../features/home/around_screen.dart';
import '../features/home/home_screen.dart';
import '../features/journey/journey_detail_screen.dart';
import '../features/journey/journey_request.dart';
import '../features/journey/journey_screen.dart';
import '../features/lines/line_screen.dart';
import '../features/onboarding/onboarding.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/search/search_screen.dart';
import '../features/stops/stop_screen.dart';
import '../features/stops/timetable_screen.dart';
import '../features/traffic/traffic_screen.dart';
import '../l10n/l10n.dart';
import 'routes.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluates the redirect when the session changes, without rebuilding the router
  final authListenable = ValueNotifier<AuthStatus>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, status) => authListenable.value = status);
  ref.onDispose(authListenable.dispose);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: authListenable,
    redirect: (context, state) {
      final status = authListenable.value;
      final location = state.matchedLocation;
      final onAuthPage = location == Routes.login;

      // The requested page is kept in `from` through the splash and sign-in pages (deep links, web reloads)
      final from = state.uri.queryParameters['from'];
      final waiting = location == Routes.splash || onAuthPage;
      String withFrom(String path) => Uri(
            path: path,
            queryParameters: {'from': waiting ? (from ?? Routes.home) : state.uri.toString()},
          ).toString();

      return switch (status) {
        AuthStatus.unknown => location == Routes.splash ? null : withFrom(Routes.splash),
        // Welcome pages once per device (a restored session may skip the splash page, so from any page). The search
        // and the sign-in pages stay reachable: the welcome pages use them; the legal notice too, for whoever opens its link.
        _ when !ref.read(onboardingDoneProvider) && location != Routes.welcome && location != Routes.search && !onAuthPage &&
            location != Routes.privacy =>
          Uri(path: Routes.welcome, queryParameters: {'from': waiting ? (from ?? Routes.home) : state.uri.toString()}).toString(),
        _ when location == Routes.splash => from ?? Routes.home,
        // Signed in: back to the page that asked for it
        AuthStatus.signedIn when onAuthPage => from ?? Routes.home,
        _ => null,
      };
    },
    routes: [
      _route(path: Routes.splash, builder: (context, state) => const _SplashScreen()),
      _route(path: Routes.login, builder: (context, state) => const LoginScreen()),
      _route(path: Routes.welcome, builder: (context, state) => WelcomeScreen(from: state.uri.queryParameters['from'])),
      ShellRoute(
        pageBuilder: (context, state, child) => _instant(state, AppShell(child: child)),
        routes: [
          _route(path: Routes.home, builder: (context, state) => const HomeScreen()),
          _route(
            path: Routes.search,
            builder: (context, state) => SearchScreen(
              pickTitle: state.uri.queryParameters['pick'],
              allowCurrentLocation: state.uri.queryParameters['here'] != '0',
            ),
          ),
          _route(
            path: Routes.journeyPath,
            builder: (context, state) => JourneyScreen(request: JourneyRequest.fromQuery(state.uri.queryParameters)),
          ),
          _route(path: Routes.journeyDetail, builder: (context, state) => JourneyDetailScreen(query: state.uri.query)),
          _route(path: Routes.traffic, builder: (context, state) => const TrafficScreen()),
          _route(path: Routes.about, builder: (context, state) => const AboutScreen()),
          _route(path: Routes.privacy, builder: (context, state) => const PrivacyScreen()),
          _route(path: Routes.account, builder: (context, state) => const AccountScreen()),
          _route(path: Routes.go, builder: (context, state) => const GoScreen()),
          _route(
            path: Routes.aroundPath,
            builder: (context, state) {
              final query = state.uri.queryParameters;
              return AroundScreen(
                position: LatLng(double.tryParse(query['lat'] ?? '') ?? 0, double.tryParse(query['lon'] ?? '') ?? 0),
                name: query['name'] ?? currentL10n.place,
              );
            },
          ),
          _route(
            path: '/stops/:stopAreaId',
            builder: (context, state) => StopScreen(stopAreaId: state.pathParameters['stopAreaId']!),
          ),
          _route(
            path: '/stops/:stopAreaId/timetable',
            builder: (context, state) => TimetableScreen(
              stopAreaId: state.pathParameters['stopAreaId']!,
              lineId: state.uri.queryParameters['line'],
              date: DateTime.tryParse(state.uri.queryParameters['date'] ?? ''),
            ),
          ),
          _route(
            path: '/lines/:lineId',
            builder: (context, state) => LineScreen(lineId: state.pathParameters['lineId']!),
          ),
        ],
      ),
    ],
  );

  // The map shows the overlay of the page on top: `router.state` is that page, pushed ones included
  // (`currentConfiguration.uri` stays on the page under the pushed ones). The delegate notifies while widgets build
  // (e.g. after a redirect), when providers can't be modified: update just after.
  void updateLocation() => Future.microtask(() => ref.read(routerLocationProvider.notifier).update(
        router.state.uri.toString(),
      ));
  router.routerDelegate.addListener(updateLocation);
  ref.onDispose(() {
    router.routerDelegate.removeListener(updateLocation);
    router.dispose();
  });

  return router;
});

/// Pages switch at once, without a transition: the panel swaps them in place over the map, and only the page on top
/// takes the sheet's scroll controller ([PanelScrollScope]). go_router animates the pages of a material_ui
/// MaterialApp: these are the pages it built while the app's MaterialApp was still Flutter's own.
Page<void> _instant(GoRouterState state, Widget child) => NoTransitionPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: {...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      child: child,
    );

GoRoute _route({required String path, required GoRouterWidgetBuilder builder}) =>
    GoRoute(path: path, pageBuilder: (context, state) => _instant(state, builder(context, state)));

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
