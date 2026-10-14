import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/l10n.dart';

final apiTokensProvider = FutureProvider.autoDispose<List<ApiToken>>((ref) => ref.watch(mobilityApiProvider).apiTokens());

/// Personal API tokens of an admin (account page): what Bruno and scripts use since sign-in goes through Google.
/// A token's value is shown once, at its creation.
class ApiTokensSection extends ConsumerWidget {
  const ApiTokensSection({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, useRootNavigator: true, builder: (context) => const _NameDialog());
    if (name == null || name.trim().isEmpty || !context.mounted) {
      return;
    }
    try {
      final created = await ref.read(mobilityApiProvider).createApiToken(name.trim());
      ref.invalidate(apiTokensProvider);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (context) => _CreatedDialog(token: created.token),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, ApiToken token) async {
    try {
      await ref.read(mobilityApiProvider).deleteApiToken(token.id);
      ref.invalidate(apiTokensProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.apiTokensTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(l10n.apiTokensHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        AsyncView(
          value: ref.watch(apiTokensProvider),
          onRetry: () => ref.invalidate(apiTokensProvider),
          data: (tokens) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tokens.isEmpty) Text(l10n.apiTokensEmpty, style: theme.textTheme.bodyMedium),
              for (final token in tokens)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(token.name),
                  subtitle: Text(l10n.apiTokenDetails(
                    formatShortDate(token.createdAt),
                    formatShortDate(token.expiresAt),
                    token.lastUsedAt == null ? l10n.apiTokenNeverUsed : l10n.apiTokenLastUsed(formatShortDate(token.lastUsedAt!)),
                  )),
                  trailing: IconButton(
                    tooltip: l10n.apiTokenRevoke(token.name),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _revoke(context, ref, token),
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l10n.apiTokenCreate),
            onPressed: () => _create(context, ref),
          ),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController(text: 'Bruno');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.apiTokenCreate),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 100,
        decoration: InputDecoration(labelText: l10n.apiTokenName),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: Text(l10n.apiTokenCreate)),
      ],
    );
  }
}

class _CreatedDialog extends StatelessWidget {
  const _CreatedDialog({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.apiTokenCreated),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.apiTokenCopyNow),
          const SizedBox(height: 12),
          SelectableText(token, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.apiTokenCopy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.apiTokenCopied)));
            }
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
      ],
    );
  }
}
