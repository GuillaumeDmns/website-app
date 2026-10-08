import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

enum AppEnvironment { dev, prod }

/// Where the app's backend and web app are. Two environments that never mix:
/// - **prod**: `guillaumedamiens.com` (the VPS), for the prod Android flavor (`--flavor prod`), the web app served from
///   `app.guillaumedamiens.com` and builds made with `--dart-define=APP_ENV=prod`;
/// - **dev**: the backend of the development machine, `http://localhost:8080`, for everything else (a phone reaches it
///   through `adb reverse tcp:8080 tcp:8080`).
abstract final class AppConfig {
  static const _environment = String.fromEnvironment('APP_ENV');

  /// Forces the backend root, without `/api` (any environment)
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Forces the web app root used in shared links
  static const _webAppUrl = String.fromEnvironment('WEB_APP_URL');

  /// OAuth client "Guillaume web" of the Google Cloud project: Google ID tokens are issued for it (web, and Android
  /// as `serverClientId`), the backend accepts it (`application.google.client-ids`). Not a secret.
  static const googleWebClientId = '98249637445-ok2b6a7v9eckahd9mdcmbqqcthfo2rjp.apps.googleusercontent.com';

  static const prodApiUrl = 'https://guillaumedamiens.com';
  static const prodWebAppUrl = 'https://app.guillaumedamiens.com';
  static const devApiUrl = 'http://localhost:8080';
  static const devWebAppUrl = 'http://localhost:5000';

  static final environment = _resolveEnvironment();

  static bool get isDev => environment == AppEnvironment.dev;

  static AppEnvironment _resolveEnvironment() {
    if (_environment.isNotEmpty) {
      return _environment == 'prod' ? AppEnvironment.prod : AppEnvironment.dev;
    }
    // Web app: the production site is prod, any other address is a dev server (the default flavor of pubspec.yaml
    // reaches web builds too, so it says nothing there)
    if (kIsWeb) {
      return Uri.base.host == Uri.parse(prodWebAppUrl).host ? AppEnvironment.prod : AppEnvironment.dev;
    }
    return appFlavor == 'prod' ? AppEnvironment.prod : AppEnvironment.dev;
  }

  /// Backend root, without `/api`
  static String get apiBaseUrl => _apiBaseUrl.isNotEmpty ? _apiBaseUrl : (isDev ? devApiUrl : prodApiUrl);

  /// Web app root, for shared links (opened by the prod Android app too, see `web/.well-known/assetlinks.json`)
  static String get webAppUrl => _webAppUrl.isNotEmpty ? _webAppUrl : (isDev ? devWebAppUrl : prodWebAppUrl);

  /// Prefix of the keys stored on the device: a dev and a prod build on the same desktop keep their own tokens and
  /// data (on Android they are two apps, on the web two sites)
  static String get storagePrefix => isDev ? 'dev.' : '';
}
