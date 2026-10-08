import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../l10n/l10n.dart';
import 'auth_controller.dart';
import 'auth_form.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  static final _usernamePattern = RegExp(r'^[A-Za-z0-9._-]{3,50}$');
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signUp(_username.text, _email.text, _password.text);
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
      title: context.l10n.signUp,
      subtitle: context.l10n.signUpSubtitle,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _username,
                decoration: InputDecoration(labelText: context.l10n.username, prefixIcon: const Icon(Icons.person_outline)),
                autofillHints: const [AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (value) => _usernamePattern.hasMatch(value?.trim() ?? '')
                    ? null
                    : context.l10n.authUsernameRule,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: context.l10n.email, prefixIcon: const Icon(Icons.mail_outline)),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (value) => _emailPattern.hasMatch(value?.trim() ?? '') ? null : context.l10n.authInvalidEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: context.l10n.password,
                  helperText: context.l10n.passwordMinLength,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? context.l10n.passwordShow : context.l10n.passwordHide,
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                enabled: !_loading,
                validator: (value) => (value?.length ?? 0) >= 8 ? null : context.l10n.passwordMinLength,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FormErrorText(_error),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.l10n.signUpAction),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => context.go(Uri(path: Routes.login, queryParameters: GoRouterState.of(context).uri.queryParameters).toString()),
          child: Text(context.l10n.haveAccountSignIn),
        ),
      ],
    );
  }
}
