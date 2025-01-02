import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:website_app/app_settings.dart';
import 'package:website_app/services/api_repository.dart';
import 'package:website_app/utils/auth_utils.dart';
import 'login.dart';
import 'screens/map.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        )
      ),
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const MyHomePage(),
        '/login': (context) => const LoginPage(),
      },
      navigatorKey: AppSettings.navigatorState,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
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
    return _isLoggedIn ? const MyHomePage() : const LoginPage();
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text("Home"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                // Navigate to the MapScreen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MapScreen()),
                );
              },
              child: const Text('Go to Map'),
            ),
          ],
        ),
      ),
    );
  }
}
