import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on the web (/stops/IDFM:71264 instead of /#/stops/…)
  usePathUrlStrategy();

  // Inter is fetched at runtime: some widgets (chips) keep the size measured with the fallback font, so wait for it
  // before the first frame (at most 3 s, e.g. offline)
  GoogleFonts.inter();
  await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 3), onTimeout: () => const []);

  runApp(const ProviderScope(child: MobilityApp()));
}
