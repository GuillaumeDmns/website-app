import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/location/location_providers.dart';
import 'router.dart';
import 'theme.dart';

class MobilityApp extends ConsumerStatefulWidget {
  const MobilityApp({super.key});

  @override
  ConsumerState<MobilityApp> createState() => _MobilityAppState();
}

class _MobilityAppState extends ConsumerState<MobilityApp> {
  // Back from the system settings (location turned on, permission granted): look for the position again
  late final _lifecycle = AppLifecycleListener(onResume: () {
    if (ref.read(userLocationProvider).value == null) {
      ref.invalidate(userLocationProvider);
    }
  });

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _lifecycle;
    return MaterialApp.router(
      title: 'Mobilités',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
