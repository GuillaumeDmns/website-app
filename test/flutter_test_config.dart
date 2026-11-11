import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:website_app/app/theme.dart';

/// Loads the bundled Inter weights before each test file, as `main()` does before `runApp`. A font loaded while texts
/// are on screen has the engine say the fonts changed, and since Flutter 3.50 the relayout that follows is a frame
/// callback: a test ending before the next frame fails with "An animation is still running".
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  AppTheme.lightTheme;
  AppTheme.darkTheme;
  await GoogleFonts.pendingFonts();
  await testMain();
}
