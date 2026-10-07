import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The language chosen on this device, or null to follow the system's
Future<Locale?> loadLocale() async {
  final code = await LocalStore().readJson(_key);
  final locale = supportedLocales.where((locale) => locale.languageCode == code).firstOrNull;
  if (locale != null) {
    _current = lookupAppLocalizations(locale);
  }
  return locale;
}

/// The app's language: the device's choice ([loadLocale], given at startup), else the system's
class LocaleController extends Notifier<Locale> {
  LocaleController([this._initial]);

  final Locale? _initial;

  @override
  Locale build() => _initial ?? systemLocale();

  Future<void> select(Locale locale) async {
    _current = lookupAppLocalizations(locale);
    state = locale;
    await ref.read(localStoreProvider).writeJson(_key, locale.languageCode);
  }

  /// French ⇄ English
  Future<void> toggle() => select(supportedLocales.firstWhere((locale) => locale != state));
}

final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
