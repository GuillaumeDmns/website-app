import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../favorites/favorite_widgets.dart';
import '../favorites/favorites_controller.dart';
import 'onboarding.dart';

/// Shown once per device after signing in: what the app does, the location permission, home and work.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.from});

  /// Page to open at the end
  final String? from;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _pageCount = 3;

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final router = GoRouter.of(context);
    await ref.read(onboardingDoneProvider.notifier).complete();
    router.go(widget.from ?? Routes.home);
  }

  void _next() => _page == _pageCount - 1
      ? _finish()
      : _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _finish, child: const Text('Passer')),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: const [_IntroPage(), _LocationPage(), _PlacesPage()],
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
                        child: Text(_page == _pageCount - 1 ? 'C\'est parti' : 'Suivant'),
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
    return _Page(
      icon: Icons.directions_transit_filled,
      title: 'Bienvenue',
      text: 'Tous les transports d\'Île-de-France, en temps réel.',
      children: [
        feature(Icons.near_me_outlined, 'Autour de vous', 'Les prochains passages aux arrêts proches, sans rien chercher.'),
        feature(Icons.alt_route, 'Itinéraires', 'Métro, RER, train, tram et bus, avec les horaires en temps réel.'),
        feature(Icons.traffic_outlined, 'Info trafic', 'Perturbations, travaux et ascenseurs en panne sur vos lignes.'),
        feature(Icons.star_outline, 'Favoris', 'Vos lieux, arrêts et lignes, sur tous vos appareils.'),
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
      title: 'Votre position',
      text: 'Elle sert à afficher les départs autour de vous et à partir de là où vous êtes. Elle n\'est envoyée que '
          'pour trouver les arrêts proches et calculer vos trajets.',
      children: [
        switch (position) {
          AsyncValue(value: _?) => ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green.shade600),
              title: const Text('Position trouvée'),
            ),
          AsyncValue(isLoading: true) => const Center(child: CircularProgressIndicator()),
          _ when issue != null && mobile => FilledButton.tonalIcon(
              icon: const Icon(Icons.my_location),
              label: Text(issue == LocationIssue.serviceDisabled ? 'Activer la localisation' : 'Autoriser la localisation'),
              onPressed: () => fixLocationIssue(ref, issue),
            ),
          _ => Text(
              'Position indisponible : vous pourrez toujours choisir un point de départ.',
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
          subtitle: Text(favorite?.label ?? 'Ajouter une adresse', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(favorite == null ? Icons.add : Icons.edit_outlined),
          onTap: () => chooseFavoritePlace(context, ref, kind),
        ),
      );
    }

    return _Page(
      icon: Icons.home_work_outlined,
      title: 'Maison et travail',
      text: 'Pour y aller en un geste depuis l\'accueil. Vous pourrez les changer plus tard.',
      children: [
        place(FavoriteKind.home, Icons.home_outlined, 'Maison'),
        place(FavoriteKind.work, Icons.work_outline, 'Travail'),
      ],
    );
  }
}
