import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/offline/offline_cache.dart';
import '../../core/storage/local_store.dart';
import '../home_widget/home_widget_sync.dart';
import 'google/google_auth.dart';

/// [guest]: the app is used without account (guest token, capped usage, data on the device only)
enum AuthStatus { unknown, guest, signedIn }

/// Session state. Signed in as long as a refresh token is stored, a guest otherwise; the interceptor reports when the
/// refresh token is rejected.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _restore();
    return AuthStatus.unknown;
  }

  Future<void> _restore() async {
    final tokenStore = ref.read(tokenStoreProvider);
    try {
      await tokenStore.load();
    } catch (_) {
      // Unreadable storage (e.g. keyring locked): carry on as a guest
    }
    state = tokenStore.signedIn ? AuthStatus.signedIn : AuthStatus.guest;
  }

  /// The account's copies on the device (favorites, recent searches…) must not stay once it is gone
  Future<void> _clearUserData() async {
    final store = ref.read(localStoreProvider);
    await store.remove('favorites');
    await store.remove('recent_searches');
    await store.remove('go_session');
    await store.remove('journey_preferences');
    await OfflineCacheInterceptor.clear(store);
    await clearHomeWidget();
  }

  /// What was saved as a guest stays: the favorites join the account (see `FavoritesController`)
  Future<void> signIn(String username, String password) async {
    final tokens = await ref.read(authApiProvider).signIn(username.trim(), password);
    await _signedIn(tokens);
  }

  Future<void> signUp(String username, String email, String password) async {
    final tokens = await ref.read(authApiProvider).signUp(username.trim(), email.trim(), password);
    await _signedIn(tokens);
  }

  Future<void> signInWithGoogle(String idToken) async {
    final tokens = await ref.read(authApiProvider).google(idToken);
    await _signedIn(tokens);
  }

  Future<void> _signedIn(AuthTokens tokens) async {
    await OfflineCacheInterceptor.clear(ref.read(localStoreProvider));
    await ref.read(tokenStoreProvider).save(tokens);
    state = AuthStatus.signedIn;
  }

  Future<void> signOut() async {
    final tokenStore = ref.read(tokenStoreProvider);
    final refreshToken = tokenStore.refreshToken;
    if (refreshToken != null) {
      await ref.read(authApiProvider).logout(refreshToken);
    }
    await tokenStore.clear();
    await _clearUserData();
    await signOutOfGoogle();
    state = AuthStatus.guest;
  }

  /// Deletes the account on the server, then forgets it here: the app carries on as a guest
  Future<void> deleteAccount() async {
    await ref.read(mobilityApiProvider).deleteAccount();
    await ref.read(tokenStoreProvider).clear();
    await _clearUserData();
    await signOutOfGoogle();
    state = AuthStatus.guest;
  }

  /// The refresh token was rejected: the app carries on as a guest
  Future<void> onSessionLost() async {
    await _clearUserData();
    state = AuthStatus.guest;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);
