import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/platform/share.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/l10n.dart';
import 'auth_controller.dart';

final accountProvider = FutureProvider.autoDispose<Account>((ref) => ref.watch(mobilityApiProvider).account());

/// The signed-in user's account: who, export of what the server keeps, sign-out, deletion. Also the web page to
/// delete an account that Google Play asks for (`/account`, signing in first).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = ref.watch(authControllerProvider);

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
              child: Text(l10n.accountTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: switch (status) {
            AuthStatus.signedIn => AsyncView(
              value: ref.watch(accountProvider),
              onRetry: () => ref.invalidate(accountProvider),
              data: (account) => _SignedIn(account: account),
            ),
            AuthStatus.guest => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.accountGuest),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(l10n.signInAction),
                  onPressed: () => context.go(Routes.signIn(Routes.account)),
                ),
              ],
            ),
            AuthStatus.unknown => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _SignedIn extends ConsumerStatefulWidget {
  const _SignedIn({required this.account});

  final Account account;

  @override
  ConsumerState<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends ConsumerState<_SignedIn> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final text = await ref.read(mobilityApiProvider).exportAccount();
      if (mounted) {
        await exportText(context, title: context.l10n.accountExport, fileName: 'account.json', text: text);
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountDeleteQuestion),
        content: Text(l10n.accountDeleteText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.accountDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    } catch (e) {
      _showError(e);
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final account = widget.account;
    final name = account.firstName ?? account.email ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase())),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: account.firstName != null && account.email != null ? Text(account.email!) : null,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.accountDataHint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(l10n.accountExport),
                onPressed: _busy ? null : _export,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.signOut),
                onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(l10n.accountDangerZone, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: Text(l10n.accountDelete),
            onPressed: _busy ? null : _delete,
          ),
        ),
      ],
    );
  }
}
