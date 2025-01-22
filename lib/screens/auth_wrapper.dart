import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:website_app/screens/home.dart';

import '../app_settings.dart';
import '../services/api_repository.dart';
import '../utils/auth_utils.dart';
import 'login.dart';
import 'map.dart';

class AuthWrapperScreen extends StatefulWidget {
  const AuthWrapperScreen({super.key});

  @override
  State<AuthWrapperScreen> createState() => _AuthWrapperScreenState();
}

class _AuthWrapperScreenState extends State<AuthWrapperScreen> {
  final _storage = const FlutterSecureStorage();
  final api = ApiRepository();
  bool _isLoggedIn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final token = await _storage.read(key: 'jwt');
    final isExpired = AuthUtils.isTokenExpired(token);

    if (token != null) {
      if (isExpired) {
        Navigator.pushReplacementNamed(AppSettings.navigatorState.currentContext!, '/login');
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}