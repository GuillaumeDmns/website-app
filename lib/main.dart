import 'package:flutter/material.dart';
import 'package:website_app/app_settings.dart';
import 'package:website_app/screens/auth_wrapper.dart';
import 'package:website_app/screens/home.dart';
import 'package:website_app/screens/map.dart';
import 'screens/login.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guillaume Damiens',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        )
      ),
      home: const AuthWrapperScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/map': (context) => const MapScreen(),
        '/home': (context) => const HomeScreen(),
      },
      navigatorKey: AppSettings.navigatorState,
    );
  }
}
