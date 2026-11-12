import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

export 'desktop_entry_stub.dart' if (dart.library.io) 'desktop_entry_io.dart' show registerDesktopEntry;

/// The name of the Linux app's desktop entry: GNOME on Wayland matches a window with the entry named after its app id
/// (`APPLICATION_ID` in `linux/CMakeLists.txt`) and shows that entry's icon in the dock; a generic one without it
const desktopEntryId = 'com.guillaumedamiens.app';

/// The line marking the entries the app writes: it never replaces another one (the user's own)
const desktopEntryMarker = 'X-Generated-By=website_app';

/// The Linux app's desktop entry (freedesktop.org's Desktop Entry Specification) for the bundle whose binary is
/// [executable]: its name, [icon], and `TryExec`, which hides the entry once the bundle is gone
String desktopEntry({required String executable, required String icon}) {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));
  return [
    '[Desktop Entry]',
    'Type=Application',
    'Name=${_escape(en.appTitle)}',
    'Name[fr]=${_escape(fr.appTitle)}',
    'Comment=${_escape(en.welcomeText)}',
    'Comment[fr]=${_escape(fr.welcomeText)}',
    'Exec=${_escape(desktopExecArgument(executable))}',
    'TryExec=${_escape(executable)}',
    'Icon=${_escape(icon)}',
    'Terminal=false',
    'Categories=Utility;Maps;',
    'StartupNotify=true',
    'StartupWMClass=$desktopEntryId',
    desktopEntryMarker,
    '',
  ].join('\n');
}

/// [path] as one argument of `Exec`: quoted, the characters reserved inside quotes escaped, `%` doubled (a field code
/// otherwise). The value's own escaping comes after
String desktopExecArgument(String path) =>
    '"${path.replaceAllMapped(RegExp(r'["`$\\]'), (match) => '\\${match[0]}').replaceAll('%', '%%')}"';

/// A string value of the entry, its backslashes and control characters escaped
String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll('\t', r'\t').replaceAll('\r', r'\r');
