import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _isAuthenticating = false;
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkSupportAndAutoLogin();
  }

  Future<void> _checkSupportAndAutoLogin() async {
    bool canCheckBiometrics = false;
    try {
      canCheckBiometrics =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } on PlatformException catch (e) {
      debugPrint("Erreur lors de la vérification du support : $e");
      canCheckBiometrics = false;
    }

    if (!mounted) return;

    setState(() {
      _canCheckBiometrics = canCheckBiometrics;
    });

    if (_canCheckBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForBiometricLogin();
      });
    }
  }

  Future<void> _login(BuildContext context) async {
    final loginSuccess = await api.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    if (loginSuccess) {
      await _storage.write(key: 'username', value: _usernameController.text);
      await _storage.write(key: 'password', value: _passwordController.text);
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed')),
      );
    }
  }

  Future<void> _authenticateBiometrically() async {
    bool authenticated = false;

    try {
      setState(() {
        _isAuthenticating = true;
      });

      authenticated = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à l\'app',
        biometricOnly: true,
      );

      setState(() {
        _isAuthenticating = false;
      });
    } on LocalAuthException catch (e) {
      setState(() {
        _isAuthenticating = false;
      });

      if (!mounted) return;

      String errorMessage = "Erreur d'authentification";
      bool shouldShowError = true;

      switch (e.code) {
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noCredentialsSet:
          errorMessage =
              "Biométrie non disponible ou non configurée sur cet appareil";
          break;

        case LocalAuthExceptionCode.temporaryLockout:
          errorMessage =
              "Trop de tentatives, biométrie temporairement verrouillée";
          break;

        case LocalAuthExceptionCode.biometricLockout:
          errorMessage =
              "Biométrie désactivée (trop d'échecs), utilisez le mot de passe";
          break;

        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.userRequestedFallback:
          shouldShowError = false;
          break;

        default:
          errorMessage = "Erreur biométrique : ${e.description ?? 'Inconnue'}";
          break;
      }

      if (shouldShowError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
      return;
    }

    if (authenticated) {
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');

      if (username != null && password != null) {
        final loginSuccess = await api.login(username, password);

        if (!mounted) return;

        if (loginSuccess) {
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Biometric login failed (Credentials invalid)')),
      );
    }
  }

  Future<void> _checkForBiometricLogin() async {
    final token = await _storage.read(key: 'jwt');

    if (token != null && !AuthUtils.isTokenExpired(token)) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }

    final username = await _storage.read(key: 'username');
    final password = await _storage.read(key: 'password');

    if (username != null && password != null) {
      await _authenticateBiometrically();
    }
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
            if (_isAuthenticating)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: () => _login(context),
                child: const Text('Login'),
              ),
            if (_canCheckBiometrics && !_isAuthenticating) ...[
              const SizedBox(height: 20),
              IconButton(
                icon: const Icon(Icons.fingerprint, size: 40),
                onPressed: _authenticateBiometrically,
                tooltip: "Connexion biométrique",
              ),
              const Text("Utiliser la biométrie"),
            ],
          ],
        ),
      ),
    );
  }
}
