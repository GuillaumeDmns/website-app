import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';

enum AuthStatus { unknown, signedIn, signedOut }

/// Session state. Signed in as long as a refresh token is stored; the interceptor reports when it is rejected.
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
      // Unreadable storage (e.g. keyring locked): sign in again
    }
    state = tokenStore.refreshToken != null ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  Future<void> signIn(String username, String password) async {
    final tokens = await ref.read(authApiProvider).signIn(username.trim(), password);
    await ref.read(tokenStoreProvider).save(tokens);
    state = AuthStatus.signedIn;
  }

  Future<void> signUp(String username, String email, String password) async {
    final tokens = await ref.read(authApiProvider).signUp(username.trim(), email.trim(), password);
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
    state = AuthStatus.signedOut;
  }

  void onSessionLost() {
    state = AuthStatus.signedOut;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);
