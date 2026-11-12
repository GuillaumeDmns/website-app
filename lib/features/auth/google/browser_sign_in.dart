import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/api/models.dart';
import '../../../core/platform/platforms.dart';
import 'browser_sign_in_stub.dart' if (dart.library.io) 'browser_sign_in_io.dart';

/// Google sign-in through the system browser, where Google has no SDK (Linux, Windows): the backend starts it and
/// finishes it with Google (`POST /api/auth/google/desktop`), the app only opens Google's page and waits for the
/// browser to come back to a port of its own on the loopback.
abstract class BrowserSignIn {
  /// Opens Google's page and waits for the user: the account's tokens, or null when they give up ([cancel], a
  /// refusal on Google's page, or nothing for too long)
  Future<AuthTokens?> signIn();

  /// Gives up the sign-in going on: [signIn] ends with null
  void cancel();
}

/// Linux and Windows; null elsewhere. The tests replace it.
final googleBrowserSignInProvider = Provider<BrowserSignIn?>(
  (ref) => isLinuxOrWindows ? createBrowserSignIn(ref.watch(authApiProvider)) : null,
);
