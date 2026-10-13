import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/map/main_map.dart';

void main() {
  bool usesMapLibre(TargetPlatform platform, {bool tiles = true}) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer(overrides: [mapTilesEnabledProvider.overrideWithValue(tiles)]);
    addTearDown(container.dispose);
    return container.read(useMapLibreProvider);
  }

  test('MapLibre on phones, flutter_map on desktop', () {
    expect(usesMapLibre(TargetPlatform.android), isTrue);
    expect(usesMapLibre(TargetPlatform.iOS), isTrue);
    expect(usesMapLibre(TargetPlatform.linux), isFalse);
    expect(usesMapLibre(TargetPlatform.windows), isFalse);
    expect(usesMapLibre(TargetPlatform.macOS), isFalse);
  });

  test('flutter_map without tiles (the tests)', () {
    expect(usesMapLibre(TargetPlatform.android, tiles: false), isFalse);
  });
}
