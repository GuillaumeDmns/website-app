import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/platforms.dart';
import '../core/storage/local_store.dart';
import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

const supportedLocales = [Locale('fr'), Locale('en')];

/// Texts in the app's language for code without a context: formatting helpers, notifications, the home screen
/// widget. Follows [localeProvider].
AppLocalizations get currentL10n => _current;
AppLocalizations _current = lookupAppLocalizations(systemLocale());

/// French when the device is in French, English otherwise
Locale systemLocale() =>
    PlatformDispatcher.instance.locale.languageCode == 'fr' ? const Locale('fr') : const Locale('en');

const _key = 'locale';

const _bridge = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// Texts of [currentL10n] in [locale] from now on
void useLocale(Locale locale) => _current = lookupAppLocalizations(locale);

/// Android 13+ keeps each app's language itself, on the app's page of the system settings
/// (`android/…/res/xml/locales_config.xml`): gives it [locale], if any, and tells whether the system is the one that
/// keeps the choice. False everywhere else, and where the app's native side doesn't answer (the home screen widget's
/// background isolate).
Future<bool> systemKeepsLanguage([Locale? locale]) async {
  if (!isAndroid) {
    return false;
  }
  try {
    return await _bridge.invokeMethod<bool>('appLanguage', {'language': ?locale?.languageCode}) ?? false;
  } catch (e) {
    return false;
  }
}

/// The language the app starts in: [chosen] on this device (null: the system's), and whether the system keeps the
/// choice itself ([systemKeepsLanguage])
typedef StartLanguage = ({Locale? chosen, bool keptBySystem});

/// The language chosen on this device. A choice kept by the app goes to the system that keeps it itself, once: the
/// widgets and notifications, in the system's language, then speak the app's.
Future<StartLanguage> loadLocale([LocalStore? localStore]) async {
  final store = localStore ?? LocalStore();
  final code = await store.readJson(_key);
  final locale = supportedLocales.where((locale) => locale.languageCode == code).firstOrNull;
  if (locale != null) {
    useLocale(locale);
  }
  final keptBySystem = await systemKeepsLanguage(locale);
  if (keptBySystem && locale != null) {
    await store.remove(_key);
  }
  return (chosen: locale, keptBySystem: keptBySystem);
}

/// The app's language: the device's choice ([loadLocale], given at startup), else the system's. Where the system
/// keeps the choice ([keptBySystem]), it is the app's language as the system gives it, changed from the app or from
/// the system settings alike.
class LocaleController extends Notifier<Locale> {
  LocaleController([this._initial, this.keptBySystem = false]);

  final Locale? _initial;
  final bool keptBySystem;

  /// Chosen in the app and kept by it: the system's language changing doesn't matter
  late bool _chosen = _initial != null && !keptBySystem;

  @override
  Locale build() => _initial ?? systemLocale();

  Future<void> select(Locale locale) async {
    useLocale(locale);
    state = locale;
    if (keptBySystem) {
      await systemKeepsLanguage(locale);
    } else {
      _chosen = true;
      await ref.read(localStoreProvider).writeJson(_key, locale.languageCode);
    }
  }

  /// French ⇄ English
  Future<void> toggle() => select(supportedLocales.firstWhere((locale) => locale != state));

  /// The system's language (for this app, where it has one) has changed
  void systemChanged() {
    final locale = systemLocale();
    if (!_chosen && locale != state) {
      useLocale(locale);
      state = locale;
    }
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
