import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../l10n/l10n.dart';
import '../home_widget/android_widgets.dart';
import '../journey/journey_request.dart';
import 'favorites_controller.dart';

/// The launcher shortcuts of the saved places (Android: a long press on the app's icon; each can be dragged to the
/// home screen): home then work, opening the journeys to them from here (a `launchLink`). `id`, `label` and `uri` of each, for the native side.
List<Map<String, String>> placeShortcuts(List<Favorite> favorites) => [
      for (final kind in const [FavoriteKind.home, FavoriteKind.work])
        if (favorites.where((favorite) => favorite.kind == kind).firstOrNull case final place?)
          {
            'id': kind.name,
            'label': kind == FavoriteKind.home ? currentL10n.home : currentL10n.work,
            'uri': launchLink(journeyTo(JourneyPlace.parse(
              favoritePlace(place).param,
              kind == FavoriteKind.home ? currentL10n.home : currentL10n.work,
            )!)),
          },
    ];

const _channel = MethodChannel('com.guillaumedamiens.app/widget');

/// Keeps the launcher's shortcuts as the saved places are (Android only: `AppShortcuts.kt`), from the start and at
/// each change; watched by the app
final placeShortcutsSyncProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  ref.listen(favoritesProvider, (_, favorites) async {
    final places = favorites.value;
    if (places == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setPlaceShortcuts', {'shortcuts': placeShortcuts(places)});
    } catch (e) {
      debugPrint('Launcher shortcuts not set: $e');
    }
  }, fireImmediately: true);
});
