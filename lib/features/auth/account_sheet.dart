import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/l10n.dart';
import 'account_photo.dart';
import 'account_screen.dart';
import 'auth_controller.dart';

/// Opened by the avatar of the home page's search: who uses the app first (the account, or what signing in adds),
/// then the app's few settings (language, about). One place for them, named for what it is, like the account sheet
/// of Google's apps.
Future<void> showAccountSheet(BuildContext context) {
  // The pages live in the panel's navigator: taken before the sheet, which is above it
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _AccountSheet(router: router),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final signedIn = ref.watch(authControllerProvider) == AuthStatus.signedIn;
    final account = signedIn ? ref.watch(accountProvider).value : null;

    /// Closes the sheet, then does [action]
    VoidCallback closing(VoidCallback action) => () {
          Navigator.pop(context);
          action();
        };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const AccountAvatar(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          signedIn ? account?.firstName ?? l10n.accountTitle : l10n.accountSheetGuest,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          signedIn ? account?.email ?? '' : l10n.guestModeHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: Text(l10n.accountTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: closing(() => router.push(Routes.account)),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(l10n.signInAction),
                  onPressed: closing(() => router.go(Routes.signIn(Routes.home))),
                ),
              ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(l10n.language),
              trailing: Text(l10n.otherLanguage, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              onTap: closing(() => ref.read(localeProvider.notifier).toggle()),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.about),
              trailing: const Icon(Icons.chevron_right),
              onTap: closing(() => router.push(Routes.about)),
            ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.signOut),
                onTap: closing(() => ref.read(authControllerProvider.notifier).signOut()),
              ),
          ],
        ),
      ),
    );
  }
}
