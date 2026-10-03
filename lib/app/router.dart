import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/map/map_overlay.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/home/around_screen.dart';
import '../features/home/home_screen.dart';
import '../features/journey/journey_detail_screen.dart';
import '../features/journey/journey_request.dart';
import '../features/journey/journey_screen.dart';
import '../features/lines/line_screen.dart';
import '../features/search/search_screen.dart';
import '../features/stops/stop_screen.dart';
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
      final onAuthPage = location == Routes.login || location == Routes.signup;

      // The requested page is kept in `from` through the splash and sign-in pages (deep links, web reloads)
      final from = state.uri.queryParameters['from'];
      final waiting = location == Routes.splash || onAuthPage;
      String withFrom(String path) => Uri(
            path: path,
            queryParameters: {'from': waiting ? (from ?? Routes.home) : state.uri.toString()},
          ).toString();

      return switch (status) {
        AuthStatus.unknown => location == Routes.splash ? null : withFrom(Routes.splash),
        AuthStatus.signedOut => onAuthPage ? null : withFrom(Routes.login),
        AuthStatus.signedIn when waiting => from ?? Routes.home,
        AuthStatus.signedIn => null,
      };
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (context, state) => const _SplashScreen()),
      GoRoute(path: Routes.login, builder: (context, state) => const LoginScreen()),
      GoRoute(path: Routes.signup, builder: (context, state) => const SignupScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: Routes.search,
            builder: (context, state) => SearchScreen(
              pickTitle: state.uri.queryParameters['pick'],
              allowCurrentLocation: state.uri.queryParameters['here'] != '0',
            ),
          ),
          GoRoute(
            path: Routes.journeyPath,
            builder: (context, state) => JourneyScreen(request: JourneyRequest.fromQuery(state.uri.queryParameters)),
          ),
          GoRoute(path: Routes.journeyDetail, builder: (context, state) => const JourneyDetailScreen()),
          GoRoute(
            path: Routes.aroundPath,
            builder: (context, state) {
              final query = state.uri.queryParameters;
              return AroundScreen(
                position: LatLng(double.tryParse(query['lat'] ?? '') ?? 0, double.tryParse(query['lon'] ?? '') ?? 0),
                name: query['name'] ?? 'Lieu',
              );
            },
          ),
          GoRoute(
            path: '/stops/:stopAreaId',
            builder: (context, state) => StopScreen(stopAreaId: state.pathParameters['stopAreaId']!),
          ),
          GoRoute(
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
