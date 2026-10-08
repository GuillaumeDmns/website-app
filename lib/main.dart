import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app.dart';
import 'features/home_widget/home_widget_sync.dart';
import 'features/onboarding/onboarding.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on the web (/stops/IDFM:71264 instead of /#/stops/…)
  usePathUrlStrategy();

  // Inter comes from the app's assets (assets/google_fonts), never from Google's servers. Loading it is still
  // asynchronous: some widgets (chips) keep the size measured with the fallback font, so wait for it before the first
  // frame
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/google_fonts/OFL.txt'));
  });
  GoogleFonts.inter();
  final (_, onboardingDone, locale, _) = await (
    GoogleFonts.pendingFonts().timeout(const Duration(seconds: 3), onTimeout: () => const []),
    loadOnboardingDone(),
    loadLocale(),
    initHomeWidget(),
  ).wait;

  runApp(ProviderScope(
    overrides: [
      onboardingDoneProvider.overrideWith(() => OnboardingController(onboardingDone)),
      localeProvider.overrideWith(() => LocaleController(locale)),
    ],
    child: const MobilityApp(),
  ));
}
