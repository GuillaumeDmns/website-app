import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../l10n/l10n.dart';
import 'auth_controller.dart';
import 'auth_form.dart';
import 'google/google_auth.dart';
import 'google/google_sign_in_button.dart';

/// Sign-in: with Google only. Where it is not available yet (desktop, iOS), the app is used as a guest.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle(String idToken) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle(idToken);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = kIsWeb || ref.watch(googleAccountChooserProvider) != null;
    final theme = Theme.of(context);
    return AuthFormLayout(
      title: context.l10n.signIn,
      subtitle: context.l10n.signInSubtitle,
      children: [
        if (available)
          GoogleSignInButton(onIdToken: _signInWithGoogle, enabled: !_loading)
        else
          Text(
            context.l10n.googleSignInUnavailable,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (_loading) ...[
          const SizedBox(height: 16),
          const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
        const SizedBox(height: 16),
        FormErrorText(_error),
        TextButton(
          onPressed: _loading ? null : () => context.go(GoRouterState.of(context).uri.queryParameters['from'] ?? Routes.home),
          child: Text(context.l10n.continueAsGuest),
        ),
      ],
    );
  }
}
