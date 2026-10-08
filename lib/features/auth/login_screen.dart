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

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  /// Dev convenience: `--dart-define=DEV_USERNAME=… --dart-define=DEV_PASSWORD=…` signs in automatically (not in release builds)
  static const _devUsername = String.fromEnvironment('DEV_USERNAME');
  static const _devPassword = String.fromEnvironment('DEV_PASSWORD');

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode && _devUsername.isNotEmpty && _devPassword.isNotEmpty) {
      _username.text = _devUsername;
      _password.text = _devPassword;
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

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

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = context.l10n.authMissingFields);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(_username.text, _password.text);
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
    return AuthFormLayout(
      title: context.l10n.signIn,
      subtitle: context.l10n.signInSubtitle,
      children: [
        if (googleSignInAvailable) ...[
          GoogleSignInButton(onIdToken: _signInWithGoogle, enabled: !_loading),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(context.l10n.or, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
        ],
        TextField(
          controller: _username,
          decoration: InputDecoration(labelText: context.l10n.username, prefixIcon: const Icon(Icons.person_outline)),
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          enabled: !_loading,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: context.l10n.password,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? context.l10n.passwordShow : context.l10n.passwordHide,
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          enabled: !_loading,
        ),
        const SizedBox(height: 24),
        FormErrorText(_error),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.l10n.signInAction),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => context.go(Uri(path: Routes.signup, queryParameters: GoRouterState.of(context).uri.queryParameters).toString()),
          child: Text(context.l10n.noAccountSignUp),
        ),
        TextButton(
          onPressed: _loading ? null : () => context.go(GoRouterState.of(context).uri.queryParameters['from'] ?? Routes.home),
          child: Text(context.l10n.continueAsGuest),
        ),
      ],
    );
  }
}
