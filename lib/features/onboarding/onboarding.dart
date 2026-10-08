import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';

final _key = '${AppConfig.storagePrefix}onboarding_done';

/// Whether the welcome pages were already shown on this device. Read before the app starts (see [loadOnboardingDone])
/// so that the router can decide synchronously.
class OnboardingController extends Notifier<bool> {
  OnboardingController([this._initial = false]);

  final bool _initial;

  @override
  bool build() => _initial;

  Future<void> complete() async {
    state = true;
    try {
      await SharedPreferencesAsync().setBool(_key, true);
    } catch (e) {
      debugPrint('Onboarding flag not saved: $e');
    }
  }
}

final onboardingDoneProvider = NotifierProvider<OnboardingController, bool>(OnboardingController.new);

/// Unreadable storage counts as done: better skip the welcome pages than show them on every start
Future<bool> loadOnboardingDone() async {
  try {
    return await SharedPreferencesAsync().getBool(_key).timeout(const Duration(seconds: 2)) ?? false;
  } catch (e) {
    debugPrint('Onboarding flag unreadable: $e');
    return true;
  }
}
