import 'dart:io';

import 'desktop_entry.dart';

/// Registers the running Linux bundle with the desktop (`~/.local/share/applications`): GNOME's dock then shows the
/// app's icon instead of a generic one, and the applications list has the app, until the bundle is gone (`TryExec`).
/// Written again when the bundle moves; it never stops the app.
Future<void> registerDesktopEntry() async {
  try {
    final executable = Platform.resolvedExecutable;
    // Installed next to the binary by linux/CMakeLists.txt
    final icon = File('${File(executable).parent.path}/data/app_icon.png');
    final applications = desktopApplicationsDirectory(Platform.environment);
    if (applications == null || !await icon.exists()) {
      return;
    }
    await writeDesktopEntry(applications, desktopEntry(executable: executable, icon: icon.path));
  } on Exception {
    // A read-only home, an entry there that isn't text: the app goes on without
  }
}

/// Where the user's desktop entries go: `$XDG_DATA_HOME/applications`, by default `~/.local/share/applications`
Directory? desktopApplicationsDirectory(Map<String, String> environment) {
  // Relative paths don't count (XDG Base Directory Specification)
  final dataHome = environment['XDG_DATA_HOME'] ?? '';
  if (dataHome.startsWith('/')) {
    return Directory('$dataHome/applications');
  }
  final home = environment['HOME'] ?? '';
  return home.startsWith('/') ? Directory('$home/.local/share/applications') : null;
}

/// Writes [content] as the app's entry in [applications], unless it is there already or the entry there isn't the
/// app's own (no [desktopEntryMarker]). Swapped in at once: the desktop, which watches the folder, never reads it half
/// written. Whether it wrote
Future<bool> writeDesktopEntry(Directory applications, String content) async {
  final entry = File('${applications.path}/$desktopEntryId.desktop');
  if (await entry.exists()) {
    final current = await entry.readAsString();
    if (current == content || !current.split('\n').contains(desktopEntryMarker)) {
      return false;
    }
  }
  await applications.create(recursive: true);
  // Not a .desktop file: ignored by the desktop
  final part = File('${applications.path}/.$desktopEntryId.desktop.part');
  await part.writeAsString(content, flush: true);
  await part.rename(entry.path);
  return true;
}
