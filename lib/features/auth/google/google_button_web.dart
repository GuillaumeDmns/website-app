import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import '../../../l10n/l10n.dart';

/// Google's own sign-in button (Google Identity Services): the result comes through
/// `GoogleSignIn.instance.authenticationEvents`
Widget googleWebButton() => web.renderButton(
      configuration: web.GSIButtonConfiguration(
        type: web.GSIButtonType.standard,
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        text: web.GSIButtonText.continueWith,
        shape: web.GSIButtonShape.pill,
        minimumWidth: 300,
        // The app's language, not the browser's
        locale: currentL10n.localeName,
      ),
    );
