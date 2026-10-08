/// Build-time configuration, set with `--dart-define`.
abstract final class AppConfig {
  /// Backend root, without `/api`. Local backend: `--dart-define=API_BASE_URL=http://localhost:8080`
  /// (`http://10.0.2.2:8080` from the Android emulator).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://guillaumedamiens.com');

  /// Web app root, for shared links (opened by the Android app too, see `web/.well-known/assetlinks.json`)
  static const webAppUrl = String.fromEnvironment('WEB_APP_URL', defaultValue: 'https://app.guillaumedamiens.com');
}
