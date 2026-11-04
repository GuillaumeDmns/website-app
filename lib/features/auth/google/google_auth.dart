import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config.dart';
import '../../../core/platform/platforms.dart';

/// "Continuer avec Google": the Google ID token the backend exchanges for its own tokens (`POST /api/auth/google`).
/// Android: the system account chooser (Credential Manager), the token is issued for the web client
/// ([AppConfig.googleWebClientId], `serverClientId`). iOS and macOS: Google's sign-in page, through the iOS client of
/// the flavor ([AppConfig.googleAppleClientId]), the token still issued for the web client; offered once that client
/// exists. Web: Google's own button (`google_button_web.dart`), which reports through
/// [GoogleSignIn.authenticationEvents]. Elsewhere (Linux, Windows): not offered.
bool get googleSignInAvailable => kIsWeb || isAndroid || (isApple && AppConfig.googleAppleClientId.isNotEmpty);

/// Opens the account chooser and gives the ID token (null when cancelled), where the app does it itself (Android, iOS,
/// macOS);
/// null on the web (Google's own button) and where Google sign-in is not available. The tests replace it.
final googleAccountChooserProvider = Provider<Future<String?> Function()?>(
  (ref) => !kIsWeb && googleSignInAvailable ? requestGoogleIdToken : null,
);

Future<void>? _initialized;

Future<void> initGoogleSignIn() => _initialized ??= GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? AppConfig.googleWebClientId : (isApple ? AppConfig.googleAppleClientId : null),
      serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
    );

/// Android, iOS, macOS: lets the user choose a Google account; null when they cancel
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
