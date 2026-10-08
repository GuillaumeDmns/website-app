import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/models.dart';
import '../config.dart';

/// Holds the current tokens. Signed in: the access token stays in memory (a restarted app gets a new one from the
/// persisted refresh token). Without account: the device's guest token is persisted, so that it keeps its daily
/// allowance across restarts, and kept when an account signs out.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  // A dev build keeps its own tokens (they come from another backend)
  static final _refreshTokenKey = '${AppConfig.storagePrefix}refresh_token';
  static final _guestTokenKey = '${AppConfig.storagePrefix}guest_token';
  static final _guestExpiryKey = '${AppConfig.storagePrefix}guest_token_expiry';

  /// Renew this long before the access token expires
  static const _expiryMargin = Duration(seconds: 30);

  final FlutterSecureStorage _storage;

  String? _accessToken;
  DateTime? _accessExpiry;
  String? _refreshToken;
  String? _guestToken;
  DateTime? _guestExpiry;

  bool get signedIn => _refreshToken != null;

  /// The account's access token when signed in, else the guest token
  String? get accessToken => signedIn ? _accessToken : _guestToken;

  String? get refreshToken => _refreshToken;

  bool get hasValidAccessToken {
    final (token, expiry) = signedIn ? (_accessToken, _accessExpiry) : (_guestToken, _guestExpiry);
    return token != null && expiry != null && DateTime.now().isBefore(expiry.subtract(_expiryMargin));
  }

  Future<void> load() async {
    _refreshToken = await _storage.read(key: _refreshTokenKey);
    _guestToken = await _storage.read(key: _guestTokenKey);
    _guestExpiry = DateTime.tryParse(await _storage.read(key: _guestExpiryKey) ?? '');
  }

  /// Tokens of an account
  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.jwt;
    _accessExpiry = DateTime.now().add(Duration(seconds: tokens.expiresIn ?? 300));
    if (tokens.refreshToken != null) {
      _refreshToken = tokens.refreshToken;
      await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    }
  }

  Future<void> saveGuest(AuthTokens tokens) async {
    _guestToken = tokens.jwt;
    _guestExpiry = DateTime.now().add(Duration(seconds: tokens.expiresIn ?? 300));
    await _storage.write(key: _guestTokenKey, value: _guestToken);
    await _storage.write(key: _guestExpiryKey, value: _guestExpiry!.toIso8601String());
  }

  /// Forgets the account (sign-out); the guest token stays
  Future<void> clear() async {
    _accessToken = null;
    _accessExpiry = null;
    _refreshToken = null;
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Forgets a guest token the server rejected
  Future<void> clearGuest() async {
    _guestToken = null;
    _guestExpiry = null;
    await _storage.delete(key: _guestTokenKey);
    await _storage.delete(key: _guestExpiryKey);
  }
}
