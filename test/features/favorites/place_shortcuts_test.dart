import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/favorites/place_shortcuts.dart';
import 'package:website_app/features/home_widget/android_widgets.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  useLocale(const Locale('fr'));

  test('home then work, each opening the journeys to it from here; no other favorite', () {
    final shortcuts = placeShortcuts([
      Favorite(id: 3, kind: FavoriteKind.stop, stopAreaId: chatelet.id, stop: chatelet),
      const Favorite(id: 2, kind: FavoriteKind.work, label: '10 Rue de Rivoli', lat: 48.8553, lon: 2.3610),
      const Favorite(id: 1, kind: FavoriteKind.home, label: '5 Avenue Foch', lat: 48.8738, lon: 2.2890),
      const Favorite(id: 4, kind: FavoriteKind.place, label: 'Piscine', lat: 48.86, lon: 2.35),
    ]);

    expect(shortcuts.map((shortcut) => shortcut['id']), ['home', 'work']);
    expect(shortcuts.map((shortcut) => shortcut['label']), ['Maison', 'Travail']);
    // What the app opens from it
    final link = Uri.parse(shortcuts.first['uri']!);
    expect(link.scheme, 'guillaumedamiens');
    final location = Uri.parse(withoutLaunch(link));
    expect(location.path, '/journey');
    expect(location.queryParameters, {'from': 'here', 'to': '48.873800,2.289000', 'toName': 'Maison'});
  });

  test('none without a saved home or work', () {
    expect(placeShortcuts(const []), isEmpty);
    expect(placeShortcuts([Favorite(id: 3, kind: FavoriteKind.stop, stopAreaId: chatelet.id, stop: chatelet)]), isEmpty);
  });
}
