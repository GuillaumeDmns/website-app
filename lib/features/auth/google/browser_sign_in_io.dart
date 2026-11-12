import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/api/api_exception.dart';
import '../../../core/api/auth_api.dart';
import '../../../core/api/models.dart';
import '../../../l10n/l10n.dart';
import 'browser_sign_in.dart';

BrowserSignIn? createBrowserSignIn(AuthApi api) => LoopbackBrowserSignIn(api);

/// Opens [url] in the user's browser
typedef BrowserOpener = Future<void> Function(Uri url);

/// The sign-in as the app sees it: it listens on a free port of the loopback, asks the backend to start a sign-in
/// ending there, opens Google's page in the system browser, and waits for the browser to come back to
/// `http://127.0.0.1:<port>/?code=…&state=…` (sent by the backend once Google is done). The one-time code is then
/// exchanged, with the verifier only the app has, for the account's tokens.
class LoopbackBrowserSignIn implements BrowserSignIn {
  LoopbackBrowserSignIn(this._api, {this.openBrowser = openInSystemBrowser, this.patience = const Duration(minutes: 10)});

  final AuthApi _api;
  final BrowserOpener openBrowser;

  /// How long the backend keeps a sign-in waiting for Google's page
  final Duration patience;

  /// What the browser came back with; null when the user gave up
  Completer<Map<String, String>?>? _waiting;

  @override
  Future<AuthTokens?> signIn() async {
    cancel();
    final waiting = _waiting = Completer<Map<String, String>?>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final started = await _api.startDesktopSignIn(server.port);
      if (waiting.isCompleted) {
        return null;
      }
      server.listen((request) => _answer(request, started.state, waiting));
      try {
        await openBrowser(Uri.parse(started.authorizationUrl));
      } on ProcessException {
        throw ApiException(currentL10n.browserOpenFailed);
      }
      final back = await waiting.future.timeout(patience, onTimeout: () => null);
      final code = back?['code'];
      if (back == null || back['error'] == 'access_denied') {
        return null;
      }
      if (code == null || code.isEmpty) {
        throw ApiException(currentL10n.googleSignInFailed);
      }
      return await _api.finishDesktopSignIn(code, started.verifier);
    } finally {
      if (!waiting.isCompleted) {
        waiting.complete(null);
      }
      await server.close(force: true);
    }
  }

  @override
  void cancel() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(null);
    }
  }

  /// The browser coming back from the backend gets a page saying to return to the app. Anything else knocking on the
  /// port (a favicon, another program, a second visit) is not this sign-in: 404.
  Future<void> _answer(HttpRequest request, String state, Completer<Map<String, String>?> waiting) async {
    final response = request.response;
    try {
      final back = request.uri.queryParameters;
      if (request.method != 'GET' || request.uri.path != '/' || back['state'] != state || waiting.isCompleted) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final l10n = currentL10n;
      final message = switch (back) {
        {'code': final code} when code.isNotEmpty => l10n.browserSignInDone,
        {'error': 'access_denied'} => l10n.browserSignInCancelled,
        _ => l10n.googleSignInFailed,
      };
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('Referrer-Policy', 'no-referrer')
        ..write(_page(l10n.appTitle, message));
      await response.close();
      if (!waiting.isCompleted) {
        waiting.complete(back);
      }
    } catch (_) {
      // The browser went away before the answer: the sign-in goes on with what it brought, or waits for another visit
    }
  }

  /// The one-time code leaves the address bar and the history (it is used up within the second anyway)
  static String _page(String title, String message) {
    const escape = HtmlEscape();
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark">'
        '<title>${escape.convert(title)}</title></head>'
        '<body style="font-family: system-ui, sans-serif; display: grid; place-items: center; min-height: 90vh; margin: 0 16px; text-align: center">'
        '<p>${escape.convert(message)}</p><script>history.replaceState(null, "", "/")</script></body></html>';
  }
}

/// The system's default browser, started on its own: `xdg-open` on Linux, the shell's URL handler on Windows. [url]
/// goes as one argument, never through a command line a shell would read.
Future<void> openInSystemBrowser(Uri url) async {
  if (url.scheme != 'https' && url.scheme != 'http') {
    throw ArgumentError.value(url, 'url', 'Not a web page');
  }
  final (command, arguments) = Platform.isWindows
      ? ('rundll32', ['url.dll,FileProtocolHandler', url.toString()])
      : (Platform.isMacOS ? 'open' : 'xdg-open', [url.toString()]);
  await Process.start(command, arguments, mode: ProcessStartMode.detached);
}
