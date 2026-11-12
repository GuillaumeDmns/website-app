import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/models.dart';
import '../../../l10n/l10n.dart';
import 'browser_sign_in.dart';
import 'google_auth.dart';
import 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';

/// "Continuer avec Google": Google's button on the web, a button opening the account chooser on Android; [onIdToken]
/// gets the Google ID token. On Linux and Windows the button opens Google's page in the system browser and waits for
/// it (with a way to give up); [onTokens] gets the account's tokens. Nothing where Google sign-in is not available.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key, required this.onIdToken, required this.onTokens, this.enabled = true});

  final Future<void> Function(String idToken) onIdToken;
  final Future<void> Function(AuthTokens tokens) onTokens;
  final bool enabled;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool _ready = !kIsWeb;
  String? _error;

  /// The sign-in going on in the system browser
  BrowserSignIn? _inBrowser;

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
    _inBrowser?.cancel();
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
      setState(() => _error = error is ApiException ? error.message : context.l10n.googleSignInFailed);
    }
  }

  Future<void> _signInInBrowser(BrowserSignIn browser) async {
    setState(() {
      _error = null;
      _inBrowser = browser;
    });
    try {
      final tokens = await browser.signIn();
      if (mounted) {
        setState(() => _inBrowser = null);
      }
      if (tokens != null) {
        await widget.onTokens(tokens);
      }
    } catch (e) {
      _onError(e);
    } finally {
      if (mounted && _inBrowser != null) {
        setState(() => _inBrowser = null);
      }
    }
  }

  Future<void> _chooseAccount(Future<String?> Function() chooser) async {
    setState(() => _error = null);
    try {
      final idToken = await chooser();
      if (idToken != null) {
        await widget.onIdToken(idToken);
      }
    } catch (e) {
      _onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chooser = ref.watch(googleAccountChooserProvider);
    final browser = kIsWeb || chooser != null ? null : ref.watch(googleBrowserSignInProvider);
    if (!kIsWeb && chooser == null && browser == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final button = kIsWeb
        ? (_ready ? Center(child: SizedBox(height: 44, child: googleWebButton())) : const SizedBox(height: 44))
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(context.l10n.continueWithGoogle),
            onPressed: widget.enabled && _inBrowser == null
                ? () => chooser != null ? _chooseAccount(chooser) : _signInInBrowser(browser!)
                : null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(ignoring: !widget.enabled, child: button),
        if (_inBrowser != null) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.browserSignInWaiting,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextButton(onPressed: _inBrowser?.cancel, child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
