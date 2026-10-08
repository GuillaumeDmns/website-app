import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../l10n/l10n.dart';

/// The app, where its data come from (with their licences) and the open source licences of its packages
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget credit(IconData icon, String title, String text) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(text),
        );

    return ListView(
      controller: PanelScrollScope.of(context),
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
            ),
            Expanded(
              child: Text(l10n.aboutTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(l10n.appTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(l10n.welcomeText, style: TextStyle(color: muted)),
              const SizedBox(height: 20),
              Text(l10n.aboutData, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              credit(Icons.directions_transit, l10n.creditIdfmTitle, l10n.creditIdfm),
              credit(Icons.alt_route, l10n.creditNavitiaTitle, l10n.creditNavitia),
              credit(Icons.map_outlined, l10n.creditIgnTitle, l10n.creditIgn),
              credit(Icons.timeline, l10n.creditOsmTitle, l10n.creditOsm),
              credit(Icons.pedal_bike, l10n.creditVelibTitle, l10n.creditVelib),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: Text(l10n.aboutLicenses),
                  // Above the whole app, not inside the panel
                  onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                    builder: (context) => LicensePage(
                      applicationName: context.l10n.appTitle,
                      applicationLegalese: '© 2026 Guillaume Damiens',
                    ),
                  )),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
