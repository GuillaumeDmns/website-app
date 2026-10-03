import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
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
      title: 'Créer un compte',
      subtitle: 'Gratuit, pour accéder au temps réel et sauvegarder vos favoris',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Nom d\'utilisateur', prefixIcon: Icon(Icons.person_outline)),
                autofillHints: const [AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (value) => _usernamePattern.hasMatch(value?.trim() ?? '')
                    ? null
                    : '3 à 50 lettres, chiffres, « . », « _ » ou « - »',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (value) => _emailPattern.hasMatch(value?.trim() ?? '') ? null : 'Email invalide',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  helperText: '8 caractères minimum',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Afficher' : 'Masquer',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                enabled: !_loading,
                validator: (value) => (value?.length ?? 0) >= 8 ? null : '8 caractères minimum',
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
              : const Text('Créer mon compte'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => context.go(Uri(path: Routes.login, queryParameters: GoRouterState.of(context).uri.queryParameters).toString()),
          child: const Text('Déjà un compte ? Se connecter'),
        ),
      ],
    );
  }
}
