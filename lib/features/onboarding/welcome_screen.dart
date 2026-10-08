import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../favorites/favorite_widgets.dart';
import '../favorites/favorites_controller.dart';
import 'onboarding.dart';

/// Shown once per device at the first start: what the app does, the location permission, home and work, then (without
/// account) what an account adds.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.from});

  /// Page to open at the end
  final String? from;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int get _pageCount => ref.read(authControllerProvider) == AuthStatus.signedIn ? 3 : 4;

  /// [signIn]: to the sign-in page, back to [WelcomeScreen.from] afterwards
  Future<void> _finish({bool signIn = false}) async {
    final router = GoRouter.of(context);
    await ref.read(onboardingDoneProvider.notifier).complete();
    final from = widget.from ?? Routes.home;
    router.go(signIn ? Routes.signIn(from) : from);
  }

  void _next() => _page == _pageCount - 1
      ? _finish()
      : _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _finish, child: Text(context.l10n.skip)),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: [
                      const _IntroPage(),
                      const _LocationPage(),
                      const _PlacesPage(),
                      if (_pageCount == 4) _AccountPage(onSignIn: () => _finish(signIn: true)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    children: [
                      for (var i = 0; i < _pageCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page ? scheme.primary : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      const Spacer(),
                      FilledButton(
                        // The theme makes filled buttons full width
                        style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                        onPressed: _next,
                        child: Text(_page == _pageCount - 1 ? context.l10n.letsGo : context.l10n.next),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.text, this.children = const []});

  final IconData icon;
  final String title;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget feature(IconData icon, String title, String text) => ListTile(
          leading: Icon(icon, color: scheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(text),
        );
    final l10n = context.l10n;
    return _Page(
      icon: Icons.directions_transit_filled,
      title: l10n.welcomeTitle,
      text: l10n.welcomeText,
      children: [
        feature(Icons.near_me_outlined, l10n.welcomeNearbyTitle, l10n.welcomeNearbyText),
        feature(Icons.alt_route, l10n.welcomeJourneysTitle, l10n.welcomeJourneysText),
        feature(Icons.traffic_outlined, l10n.welcomeTrafficTitle, l10n.welcomeTrafficText),
        feature(Icons.star_outline, l10n.welcomeFavoritesTitle, l10n.welcomeFavoritesText),
      ],
    );
  }
}

class _LocationPage extends ConsumerWidget {
  const _LocationPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(userLocationProvider);
    final issue = ref.watch(locationIssueProvider);
    final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    return _Page(
      icon: Icons.my_location,
      title: context.l10n.welcomeLocationTitle,
      text: context.l10n.welcomeLocationText,
      children: [
        switch (position) {
          AsyncValue(value: _?) => ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green.shade600),
              title: Text(context.l10n.locationFound),
            ),
          AsyncValue(isLoading: true) => const Center(child: CircularProgressIndicator()),
          _ when issue != null && mobile => FilledButton.tonalIcon(
              icon: const Icon(Icons.my_location),
              label: Text(issue == LocationIssue.serviceDisabled ? context.l10n.locationTurnOn : context.l10n.locationAllow),
              onPressed: () => fixLocationIssue(ref, issue),
            ),
          _ => Text(
              context.l10n.welcomeLocationUnavailable,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
        },
      ],
    );
  }
}

class _PlacesPage extends ConsumerWidget {
  const _PlacesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    Favorite? find(FavoriteKind kind) => favorites.where((favorite) => favorite.kind == kind).firstOrNull;

    Widget place(FavoriteKind kind, IconData icon, String title) {
      final favorite = find(kind);
      return Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(favorite?.label ?? context.l10n.addAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(favorite == null ? Icons.add : Icons.edit_outlined),
          onTap: () => chooseFavoritePlace(context, ref, kind),
        ),
      );
    }

    return _Page(
      icon: Icons.home_work_outlined,
      title: context.l10n.welcomePlacesTitle,
      text: context.l10n.welcomePlacesText,
      children: [
        place(FavoriteKind.home, Icons.home_outlined, context.l10n.home),
        place(FavoriteKind.work, Icons.work_outline, context.l10n.work),
      ],
    );
  }
}

/// Without account: the limits, and what signing in adds
class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Page(
      icon: Icons.account_circle_outlined,
      title: l10n.welcomeAccountTitle,
      text: l10n.welcomeAccountText,
      children: [
        FilledButton.tonalIcon(icon: const Icon(Icons.login), label: Text(l10n.signInAction), onPressed: onSignIn),
      ],
    );
  }
}
