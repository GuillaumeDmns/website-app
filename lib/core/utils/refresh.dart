import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_shown.dart';

/// Whether something follows real-time data with the app off screen: GO, whose foreground service keeps the app
/// running with the screen off. Only the providers asking for it ([RefreshEvery.refreshEvery]'s `whileFollowed`) go on
/// then.
class FollowedOffScreen extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool followed) => state = followed;
}

final followedOffScreenProvider = NotifierProvider<FollowedOffScreen, bool>(FollowedOffScreen.new);

extension RefreshEvery on Ref {
  /// Fetches the provider again after [period], while it is used (Riverpod pauses providers that aren't shown) and the
  /// app is on screen ([appShownProvider]): with the screen off, in the background, in a hidden browser tab or a
  /// minimized window, nobody sees it, and each fetch costs battery and the backend's quotas (GO's service keeps the
  /// app running for a whole journey). A period ending off screen is fetched once the app is back. With
  /// [whileFollowed], it goes on off screen while [followedOffScreenProvider] says so (the departures GO follows).
  /// With [reloadWhenHidden], a period ending while it is paused or off screen makes the next fetch a reload
  /// ([AsyncValue.isReloading], its value kept meanwhile): what it holds by then is outdated, for its readers not to
  /// show.
  void refreshEvery(Duration period, {bool reloadWhenHidden = false, bool whileFollowed = false}) {
    bool seen() => read(appShownProvider) || (whileFollowed && read(followedOffScreenProvider));
    var due = false;
    final timer = Timer(period, () {
      if (seen()) {
        invalidateSelf(asReload: reloadWhenHidden && isPaused);
      } else {
        due = true;
      }
    });
    onDispose(timer.cancel);
    void catchUp() {
      if (due && seen()) {
        due = false;
        invalidateSelf(asReload: reloadWhenHidden);
      }
    }

    listen(appShownProvider, (_, _) => catchUp());
    if (whileFollowed) {
      listen(followedOffScreenProvider, (_, _) => catchUp());
    }
  }
}

/// The time now, then every [period] while the app is on screen ([shown]): off screen nothing is drawn, and a clock
/// would wake the app for nothing. Back on screen, the provider watching [appShownProvider] starts it again, from now.
Stream<DateTime> clockEvery(Duration period, {required bool shown}) async* {
  yield DateTime.now();
  if (shown) {
    yield* Stream.periodic(period, (_) => DateTime.now());
  }
}
