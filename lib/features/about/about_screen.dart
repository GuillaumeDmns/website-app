import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/config.dart';
import '../../l10n/l10n.dart';

/// The app, its version (for bug reports), where its data come from (with their licences) and the open source licences of its packages
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final server = ref.watch(serverVersionProvider).value;
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
              child: Text(l10n.aboutTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(l10n.appTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(l10n.welcomeText, style: TextStyle(color: muted)),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.aboutVersion, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        SelectableText(appVersionLabel(l10n)),
                        SelectableText(appBuildDetails(l10n, server: server), style: TextStyle(color: muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.aboutCopyVersion,
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '${l10n.appTitle} ${appVersionLabel(l10n)} · ${appBuildDetails(l10n, server: server)}'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.aboutVersionCopied)));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(l10n.aboutData, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              credit(Icons.directions_transit, l10n.creditIdfmTitle, l10n.creditIdfm),
              credit(Icons.alt_route, l10n.creditNavitiaTitle, l10n.creditNavitia),
              credit(Icons.map_outlined, l10n.creditIgnTitle, l10n.creditIgn),
              credit(Icons.timeline, l10n.creditOsmTitle, l10n.creditOsm),
              credit(Icons.pedal_bike, l10n.creditVelibTitle, l10n.creditVelib),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                  label: Text(l10n.privacy),
                  onPressed: () => context.push(Routes.privacy),
                ),
              ),
              const SizedBox(height: 8),
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

/// The version of the build: `0.4.0 (40000)` from git's tag (`tool/build.sh`), else a development build
String appVersionLabel(AppLocalizations l10n, {String version = AppConfig.version, String build = AppConfig.build}) =>
    version.isEmpty ? l10n.aboutDevBuild : '$version ($build)';

/// What else a bug report needs: the commit, the environment, the backend and its release, the platform
String appBuildDetails(AppLocalizations l10n, {String commit = AppConfig.commit, String? server}) => [
      if (commit.isNotEmpty) 'commit $commit',
      AppConfig.environment.name,
      Uri.parse(AppConfig.apiBaseUrl).host,
      if (server != null) l10n.aboutServerVersion(server),
      AppConfig.platform,
    ].join(' · ');

/// The backend's release (`/api/health`: the tag of its jar, "dev" otherwise), null when it doesn't answer
final serverVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final response = await ref.watch(apiDioProvider).get<Map<String, dynamic>>('/api/health');
    return response.data?['version'] as String?;
  } catch (_) {
    return null;
  }
});
