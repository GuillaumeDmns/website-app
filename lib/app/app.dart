import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/location/location_providers.dart';
import '../features/home_widget/home_widget_sync.dart';
import '../l10n/l10n.dart';
import 'router.dart';
import 'theme.dart';

class MobilityApp extends ConsumerStatefulWidget {
  const MobilityApp({super.key});

  @override
  ConsumerState<MobilityApp> createState() => _MobilityAppState();
}

class _MobilityAppState extends ConsumerState<MobilityApp> {
  // Back from the system settings (location turned on, permission granted): look for the position again, where a page
  // uses it (not the widget's setup, which never asks for it)
  late final _lifecycle = AppLifecycleListener(onResume: () {
    if (ref.read(userLocationProvider.exists) && ref.read(userLocationProvider).value == null) {
      ref.invalidate(userLocationProvider);
    }
  });

  /// A home screen widget tapped while the app runs: its stop, or its setup
  StreamSubscription<String>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    _widgetClicks = ref.read(widgetClicksProvider).listen((location) => ref.read(routerProvider).push(location));
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
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
        final app = KeyedSubtree(
          key: ValueKey(locale),
          // flutter_map, vector_map_tiles and maplibre still build their widgets (the attribution, …) from Flutter's own
          // Material library, which only reads its own ThemeData and MaterialLocalizations: the bridge gives them
          // the app's. To drop once they have moved to material_ui.
          // ignore: deprecated_member_use
          child: MaterialUiCompatibilityBridge(child: child!),
        );
        // Never mistaken for the production app
        return AppConfig.isDev
            ? Banner(message: 'DEV', location: BannerLocation.topEnd, color: Colors.orange.shade800, child: app)
            : app;
      },
    );
  }
}
