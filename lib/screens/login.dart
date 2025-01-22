import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:website_app/services/api_repository.dart';
import 'package:website_app/utils/auth_utils.dart';

import '../app_settings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  final api = ApiRepository();

  Future<void> _login(BuildContext context) async {
    final loginSuccess = await api.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (loginSuccess) {
      await _storage.write(key: 'username', value: _usernameController.text);
      await _storage.write(key: 'password', value: _passwordController.text);
      Navigator.pushReplacementNamed(AppSettings.navigatorState.currentContext!, '/home');
    } else {
      ScaffoldMessenger.of(AppSettings.navigatorState.currentContext!).showSnackBar(
        const SnackBar(content: Text('Login failed')),
      );
    }
  }

  Future<void> _authenticateBiometrically() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à l\'app',
        options: const AuthenticationOptions(biometricOnly: true),
      );

      if (authenticated) {
        final username = await _storage.read(key: 'username');
        final password = await _storage.read(key: 'password');

        if (username != null && password != null) {
          final loginSuccess = await api.login(username, password);

          if (loginSuccess) {
            Navigator.pushReplacementNamed(AppSettings.navigatorState.currentContext!, '/home');
            return;
          }
        }
        ScaffoldMessenger.of(AppSettings.navigatorState.currentContext!).showSnackBar(
          const SnackBar(content: Text('Biometric login failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(AppSettings.navigatorState.currentContext!).showSnackBar(
        SnackBar(content: Text('Erreur biométrique : $e')),
      );
    }
  }

  Future<void> _checkForBiometricLogin() async {
    final token = await _storage.read(key: 'jwt');
    if (token == null || AuthUtils.isTokenExpired(token)) {
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');

      if (username != null && password != null) {
        await _authenticateBiometrically();
      }
    } else {
      Navigator.pushReplacementNamed(AppSettings.navigatorState.currentContext!, '/home');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForBiometricLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _login(context),
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
