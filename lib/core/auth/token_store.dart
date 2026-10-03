import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/models.dart';

/// Holds the current tokens in memory and persists the refresh token. The access token is kept in memory only:
/// a restarted app gets a new one from the refresh token.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'refresh_token';

  /// Refresh this long before the access token expires
  static const _expiryMargin = Duration(seconds: 30);

  final FlutterSecureStorage _storage;

  String? _accessToken;
  DateTime? _accessExpiry;
  String? _refreshToken;

  String? get accessToken => _accessToken;

  String? get refreshToken => _refreshToken;

  bool get hasValidAccessToken =>
      _accessToken != null && _accessExpiry != null && DateTime.now().isBefore(_accessExpiry!.subtract(_expiryMargin));

  Future<void> load() async {
    _refreshToken = await _storage.read(key: _refreshTokenKey);
  }

  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.jwt;
    _accessExpiry = DateTime.now().add(Duration(seconds: tokens.expiresIn ?? 300));
    if (tokens.refreshToken != null) {
      _refreshToken = tokens.refreshToken;
      await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    }
  }

  Future<void> clear() async {
    _accessToken = null;
    _accessExpiry = null;
    _refreshToken = null;
    await _storage.delete(key: _refreshTokenKey);
  }
}
