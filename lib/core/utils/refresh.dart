import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

extension RefreshEvery on Ref {
  /// Fetches the provider again after [period], while it is used (Riverpod pauses providers that aren't shown). With
  /// [reloadWhenHidden], a period ending while it is paused makes the next fetch a reload ([AsyncValue.isReloading],
  /// its value kept meanwhile): what it holds by then is outdated, for its readers not to show.
  void refreshEvery(Duration period, {bool reloadWhenHidden = false}) {
    final timer = Timer(period, () => invalidateSelf(asReload: reloadWhenHidden && isPaused));
    onDispose(timer.cancel);
  }
}
