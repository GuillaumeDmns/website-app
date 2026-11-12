import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/platform/desktop_entry.dart';
import 'package:website_app/core/platform/desktop_entry_io.dart';
import 'package:website_app/l10n/l10n.dart';

/// The Linux app's desktop entry: GNOME shows its icon in the dock
void main() {
  const executable = '/opt/website_app/website_app';
  const icon = '/opt/website_app/data/app_icon.png';

  group('desktopEntry', () {
    test("names the app in both languages, opens the bundle and shows its icon", () {
      final entry = desktopEntry(executable: executable, icon: icon);
      final lines = entry.split('\n');
      expect(lines.first, '[Desktop Entry]');
      expect(entry, endsWith('\n'));
      expect(lines, containsAll([
        'Type=Application',
        'Name=Guillaume',
        'Name[fr]=Guillaume',
        'Comment=${lookupAppLocalizations(const Locale('en')).welcomeText}',
        'Comment[fr]=${lookupAppLocalizations(const Locale('fr')).welcomeText}',
        'Exec="/opt/website_app/website_app"',
        'TryExec=/opt/website_app/website_app',
        'Icon=/opt/website_app/data/app_icon.png',
        // The app id of linux/CMakeLists.txt, which X11 sessions match too
        'StartupWMClass=com.guillaumedamiens.app',
        desktopEntryMarker,
      ]));
    });

    test('quotes the binary, escaping what the quotes and the value reserve', () {
      expect(desktopExecArgument(r'/home/a b/100% "x"/$y`z\w'), r'"/home/a b/100%% \"x\"/\$y\`z\\w"');
      // A backslash: escaped inside the quotes, then as a value (four of them)
      final lines = desktopEntry(executable: r'/a\b/app', icon: icon).split('\n');
      expect(lines, containsAll([r'Exec="/a\\\\b/app"', r'TryExec=/a\\b/app']));
    });
  });

  test('desktopApplicationsDirectory: XDG_DATA_HOME, else ~/.local/share', () {
    expect(desktopApplicationsDirectory({'XDG_DATA_HOME': '/data', 'HOME': '/home/u'})?.path, '/data/applications');
    expect(desktopApplicationsDirectory({'XDG_DATA_HOME': 'data', 'HOME': '/home/u'})?.path,
        '/home/u/.local/share/applications');
    expect(desktopApplicationsDirectory({'HOME': '/home/u'})?.path, '/home/u/.local/share/applications');
    expect(desktopApplicationsDirectory({}), isNull);
  });

  group('writeDesktopEntry', () {
    late Directory home;
    late Directory applications;
    File entry() => File('${applications.path}/com.guillaumedamiens.app.desktop');

    setUp(() async {
      home = await Directory.systemTemp.createTemp('desktop_entry_test');
      applications = Directory('${home.path}/.local/share/applications');
    });
    tearDown(() => home.delete(recursive: true));

    test('creates the folder and the entry, then leaves it alone while it is the same', () async {
      final content = desktopEntry(executable: executable, icon: icon);
      expect(await writeDesktopEntry(applications, content), isTrue);
      expect(await entry().readAsString(), content);

      final written = (await entry().stat()).modified;
      expect(await writeDesktopEntry(applications, content), isFalse);
      expect((await entry().stat()).modified, written);
      // Nothing else left in the folder
      expect(applications.listSync().map((file) => file.uri.pathSegments.last), ['com.guillaumedamiens.app.desktop']);
    });

    test('follows the bundle when it moves', () async {
      await writeDesktopEntry(applications, desktopEntry(executable: executable, icon: icon));
      final moved = desktopEntry(
          executable: '/home/u/Apps/website_app/website_app', icon: '/home/u/Apps/website_app/data/app_icon.png');
      expect(await writeDesktopEntry(applications, moved), isTrue);
      expect(await entry().readAsString(), moved);
    });

    test("never replaces an entry the app didn't write", () async {
      const own = '[Desktop Entry]\nType=Application\nName=Mine\nExec=/usr/local/bin/website_app\n';
      await applications.create(recursive: true);
      await entry().writeAsString(own);
      expect(await writeDesktopEntry(applications, desktopEntry(executable: executable, icon: icon)), isFalse);
      expect(await entry().readAsString(), own);
    });
  });
}
