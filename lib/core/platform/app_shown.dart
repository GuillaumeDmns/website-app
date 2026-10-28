import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is on screen (resumed, or inactive under a system dialog or the notification shade): false with the
/// screen off or the app in the background, where what only the screen needs stops (the compass, the smoothed
/// position, the app's own location feed) and GO asks fewer fixes
class AppShown extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(onStateChange: (lifecycle) => state = shownIn(lifecycle));
    ref.onDispose(listener.dispose);
    return shownIn(WidgetsBinding.instance.lifecycleState);
  }

  /// Not known yet (before the first frame): shown
  static bool shownIn(AppLifecycleState? lifecycle) =>
      lifecycle == null || lifecycle == AppLifecycleState.resumed || lifecycle == AppLifecycleState.inactive;
}

final appShownProvider = NotifierProvider<AppShown, bool>(AppShown.new);
