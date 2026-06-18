import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:website_app/services/api_repository.dart';
import 'package:website_app/utils/app_theme.dart';
import 'package:website_app/utils/auth_utils.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  final api = ApiRepository();

  bool _isAuthenticating = false;
  bool _canCheckBiometrics = false;
  bool _obscurePassword = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _checkSupportAndAutoLogin();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    setState(() => _canCheckBiometrics = canCheckBiometrics);

    if (_canCheckBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForBiometricLogin();
      });
    }
  }

  Future<void> _login(BuildContext context) async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _isAuthenticating = true);
    final loginSuccess = await api.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    if (loginSuccess) {
      await _storage.write(key: 'username', value: _usernameController.text);
      await _storage.write(key: 'password', value: _passwordController.text);
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identifiants incorrects')),
      );
    }
  }

  Future<void> _authenticateBiometrically() async {
    bool authenticated = false;
    try {
      setState(() => _isAuthenticating = true);
      authenticated = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à l\'app',
        biometricOnly: true,
      );
      setState(() => _isAuthenticating = false);
    } on LocalAuthException catch (e) {
      setState(() => _isAuthenticating = false);
      if (!mounted) return;

      String errorMessage = "Erreur d'authentification";
      bool shouldShowError = true;

      switch (e.code) {
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noCredentialsSet:
          errorMessage = "Biométrie non disponible ou non configurée";
          break;
        case LocalAuthExceptionCode.temporaryLockout:
          errorMessage = "Trop de tentatives, biométrie temporairement verrouillée";
          break;
        case LocalAuthExceptionCode.biometricLockout:
          errorMessage = "Biométrie désactivée, utilisez le mot de passe";
          break;
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.userRequestedFallback:
          shouldShowError = false;
          break;
        default:
          errorMessage = "Erreur biométrique : ${e.description ?? 'Inconnue'}";
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
        const SnackBar(content: Text('Échec de la connexion biométrique')),
      );
    }
  }

  Future<void> _checkForBiometricLogin() async {
    final token = await _storage.read(key: 'jwt');
    if (token != null && !AuthUtils.isTokenExpired(token)) {
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              isDark
                  ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                  : AppTheme.primaryBlue.withValues(alpha: 0.04),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    // Logo
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_transit_filled,
                        size: 48,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Bienvenue',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connectez-vous pour continuer',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: 48),
                    // Username field
                    TextField(
                      controller: _usernameController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: "Nom d'utilisateur",
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        labelText: "Nom d'utilisateur",
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Password field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(context),
                      decoration: InputDecoration(
                        hintText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        labelText: 'Mot de passe',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Login button
                    if (_isAuthenticating)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: CircularProgressIndicator(),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _login(context),
                          child: const Text('Se connecter'),
                        ),
                      ),
                    // Biometric button
                    if (_canCheckBiometrics && !_isAuthenticating) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(color: colorScheme.outline.withValues(alpha: 0.5)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'ou',
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(alpha: 0.45),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: colorScheme.outline.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _authenticateBiometrically,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: BorderSide(color: colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          foregroundColor: colorScheme.onSurface,
                        ),
                        icon: const Icon(Icons.fingerprint, size: 22),
                        label: const Text('Connexion biométrique'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
