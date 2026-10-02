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

      return switch (status) {
        AuthStatus.unknown => location == Routes.splash ? null : '${Routes.splash}?from=${Uri.encodeComponent(state.uri.toString())}',
        AuthStatus.signedOut => onAuthPage ? null : Routes.login,
        AuthStatus.signedIn when location == Routes.splash => state.uri.queryParameters['from'] ?? Routes.home,
        AuthStatus.signedIn when onAuthPage => Routes.home,
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
          GoRoute(path: Routes.search, builder: (context, state) => const SearchScreen()),
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

  // The map shows the overlay of the page on top. The delegate notifies while widgets build (e.g. after a
  // redirect), when providers can't be modified: update just after.
  void updateLocation() => Future.microtask(() => ref.read(routerLocationProvider.notifier).update(
        router.routerDelegate.currentConfiguration.uri.toString(),
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
