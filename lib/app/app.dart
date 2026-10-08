import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/location/location_providers.dart';
import '../l10n/l10n.dart';
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
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      // Rebuilt from scratch when the language changes: texts formatted outside widgets (currentL10n) follow
      builder: (context, child) {
        final app = KeyedSubtree(key: ValueKey(locale), child: child!);
        // Never mistaken for the production app
        return AppConfig.isDev
            ? Banner(message: 'DEV', location: BannerLocation.topEnd, color: Colors.orange.shade800, child: app)
            : app;
      },
    );
  }
}
