import '../../../core/api/auth_api.dart';
import 'browser_sign_in.dart';

/// No port to listen on in a browser (see browser_sign_in_io.dart): the web has Google's own button
BrowserSignIn? createBrowserSignIn(AuthApi api) => null;
