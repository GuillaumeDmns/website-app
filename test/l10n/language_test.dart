import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/memory_store.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

const _bridge = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// The app's native side: the languages it was given, as Android 13+ ([keeps]: true) or an older one answers
List<String?> _system(WidgetTester tester, {required bool keeps}) {
  final given = <String?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, (call) async {
    if (call.method != 'appLanguage') {
      return null;
    }
    given.add((call.arguments as Map)['language'] as String?);
    return keeps;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, null));
  return given;
}

void main() {
  group('the language at startup', () {
    testWidgets('a choice kept by the app goes to the system that keeps it, once', (tester) async {
      final given = _system(tester, keeps: true);
      final store = MemoryStore({'locale': 'en'});

      final language = await loadLocale(store);

      expect(language, (chosen: const Locale('en'), keptBySystem: true));
      expect(given, ['en']);
      expect(store.values, isEmpty);
      expect(currentL10n.localeName, 'en');

      // The next start: nothing more to hand over, the system gives the language
      expect(await loadLocale(store), (chosen: null, keptBySystem: true));
      expect(given, ['en', null]);
    });

    testWidgets('it stays in the app where the system keeps none', (tester) async {
      final given = _system(tester, keeps: false);
      final store = MemoryStore({'locale': 'en'});

      expect(await loadLocale(store), (chosen: const Locale('en'), keptBySystem: false));
      expect(given, ['en']);
      expect(store.values, {'locale': '"en"'});
    });

    testWidgets("it stays in the app where the native side doesn't answer", (tester) async {
      // The home screen widget's background isolate
      final store = MemoryStore({'locale': 'en'});

      // The engine's own answer (no such method), which only comes in real time
      final language = await tester.runAsync(() => loadLocale(store));

      expect(language, (chosen: const Locale('en'), keptBySystem: false));
      expect(store.values, {'locale': '"en"'});
    });
  });

  group('where the system keeps the language', () {
    testWidgets('the language chosen in the app is given to it, not kept by the app', (tester) async {
      final given = _system(tester, keeps: true);
      final store = await pumpApp(tester, standardBackend(), languageKeptBySystem: true);

      await tapOn(tester, find.byTooltip(currentL10n.account));
      await tapOn(tester, find.text(currentL10n.otherLanguage));

      expect(find.text('Nearby'), findsOneWidget);
      expect(given, ['en']);
      expect(store.values.containsKey('locale'), isFalse);

      await closeApp(tester);
    });

    testWidgets('the language chosen in the system settings is the app\'s at once', (tester) async {
      await pumpApp(tester, standardBackend(), languageKeptBySystem: true);
      expect(find.text('Nearby'), findsNothing);

      tester.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await settle(tester);

      expect(find.text('Nearby'), findsOneWidget);
      expect(currentL10n.localeName, 'en');

      await closeApp(tester);
    });
  });

  testWidgets("a language chosen in the app, and kept by it, doesn't follow the system's", (tester) async {
    await pumpApp(tester, standardBackend());

    tester.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await settle(tester);

    expect(find.text('Nearby'), findsNothing);

    await closeApp(tester);
  });
}
