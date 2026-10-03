import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';

void main() {
  // Clean URLs on the web (/stops/IDFM:71264 instead of /#/stops/…)
  usePathUrlStrategy();
  runApp(const ProviderScope(child: MobilityApp()));
}
