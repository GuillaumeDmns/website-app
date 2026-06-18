import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:website_app/screens/home.dart';
import 'package:website_app/utils/app_theme.dart';

import '../app_settings.dart';
import '../services/api_repository.dart';
import '../utils/auth_utils.dart';
import 'login.dart';

class AuthWrapperScreen extends StatefulWidget {
  const AuthWrapperScreen({super.key});

  @override
  State<AuthWrapperScreen> createState() => _AuthWrapperScreenState();
}

class _AuthWrapperScreenState extends State<AuthWrapperScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final api = ApiRepository();
  bool _isLoggedIn = false;
  bool _loading = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkLoginStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final token = await _storage.read(key: 'jwt');
    final isExpired = AuthUtils.isTokenExpired(token);

    if (token != null) {
      if (isExpired) {
        Navigator.pushReplacementNamed(
            AppSettings.navigatorState.currentContext!, '/login');
      } else {
        setState(() {
          _isLoggedIn = true;
          _loading = false;
        });
      }
    } else {
      setState(() {
        _isLoggedIn = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final colorScheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surface,
                colorScheme.primary.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_transit_filled,
                      size: 44,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}