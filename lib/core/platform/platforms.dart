import 'package:flutter/foundation.dart';

/// Whether the app's own native side runs here and answers its channels (`MainActivity.kt` on Android,
/// `AppBridge.swift` on iOS and macOS): GO's ongoing notification or Live Activity, sharing, keeping the screen on
bool get hasNativeBridge => !kIsWeb && (isAndroid || isApple);

bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The desktops without a Google SDK: Google sign-in goes through the system browser there
bool get isLinuxOrWindows =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);

/// iOS or macOS (the same Swift side, `ios/` and `macos/`)
bool get isApple => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);
