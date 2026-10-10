import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

extension RefreshEvery on Ref {
  /// Fetches the provider again after [period], while it is used (Riverpod pauses providers that aren't shown)
  void refreshEvery(Duration period) {
    final timer = Timer(period, invalidateSelf);
    onDispose(timer.cancel);
  }
}
