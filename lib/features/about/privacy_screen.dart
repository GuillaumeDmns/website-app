import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../l10n/l10n.dart';

/// Legal notice and privacy policy (`/privacy`: the URL given to Google's consent screen and the Play Store). Open
/// without the welcome pages.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );
    Widget paragraph(String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SelectableText(text));

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
              child: Text(l10n.privacy, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading(l10n.privacyPublisherTitle),
              paragraph(l10n.privacyPublisher),
              heading(l10n.privacyHostTitle),
              paragraph(l10n.privacyHost),
              heading(l10n.privacyDataTitle),
              paragraph(l10n.privacyGuest),
              paragraph(l10n.privacyAccount),
              paragraph(l10n.privacyLocation),
              paragraph(l10n.privacyNoTracking),
              paragraph(l10n.privacyServices),
              heading(l10n.privacyRightsTitle),
              paragraph(l10n.privacyRights),
            ],
          ),
        ),
      ],
    );
  }
}
