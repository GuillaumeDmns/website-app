import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config.dart';

/// "Continuer avec Google": the Google ID token the backend exchanges for its own tokens (`POST /api/auth/google`).
/// Android: the system account chooser (Credential Manager), the token is issued for the web client
/// ([AppConfig.googleWebClientId], `serverClientId`). Web: Google's own button (`google_button_web.dart`), which reports
/// through [GoogleSignIn.authenticationEvents]. Elsewhere (desktop, iOS until it has its own client): not offered.
bool get googleSignInAvailable => kIsWeb || defaultTargetPlatform == TargetPlatform.android;

Future<void>? _initialized;

Future<void> initGoogleSignIn() => _initialized ??= GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? AppConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
    );

/// Android: lets the user choose a Google account; null when they cancel
Future<String?> requestGoogleIdToken() async {
  await initGoogleSignIn();
  try {
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
      return null;
    }
    rethrow;
  }
}

/// Google forgets the account chosen, so that the next sign-in asks again (after the app's sign-out)
Future<void> signOutOfGoogle() async {
  if (!googleSignInAvailable || _initialized == null) {
    return;
  }
  try {
    await GoogleSignIn.instance.signOut();
  } catch (e) {
    debugPrint('Google sign-out failed: $e');
  }
}
