import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../l10n/l10n.dart';
import 'google_auth.dart';
import 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';

/// "Continuer avec Google": Google's button on the web, a button opening the account chooser on Android; [onIdToken]
/// gets the Google ID token. Nothing where Google sign-in is not available.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.onIdToken, this.enabled = true});

  final Future<void> Function(String idToken) onIdToken;
  final bool enabled;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool _ready = !kIsWeb;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      initGoogleSignIn().then((_) {
        if (!mounted) {
          return;
        }
        _events = GoogleSignIn.instance.authenticationEvents.listen(_onEvent, onError: _onError);
        setState(() => _ready = true);
      }, onError: _onError);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    if (event case GoogleSignInAuthenticationEventSignIn(:final user)) {
      final idToken = user.authentication.idToken;
      if (idToken != null) {
        widget.onIdToken(idToken);
      }
    }
  }

  void _onError(Object error) {
    debugPrint('Google sign-in failed: $error');
    if (mounted) {
      setState(() => _error = context.l10n.googleSignInFailed);
    }
  }

  Future<void> _chooseAccount() async {
    setState(() => _error = null);
    try {
      final idToken = await requestGoogleIdToken();
      if (idToken != null) {
        await widget.onIdToken(idToken);
      }
    } catch (e) {
      _onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!googleSignInAvailable) {
      return const SizedBox.shrink();
    }
    final button = kIsWeb
        ? (_ready ? Center(child: SizedBox(height: 44, child: googleWebButton())) : const SizedBox(height: 44))
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(context.l10n.continueWithGoogle),
            onPressed: widget.enabled ? _chooseAccount : null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(ignoring: !widget.enabled, child: button),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
