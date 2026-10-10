import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/search/recent_searches.dart';

import '../../support/fake_backend.dart';
import '../../support/memory_store.dart';
import '../../support/samples.dart';
import '../../support/test_container.dart';

void main() {
  const rivoli = PlaceResult(type: PlaceType.address, id: '2.34;48.86', name: '10 Rue de Rivoli', lat: 48.86, lon: 2.34);

  test('keeps the ten latest choices, most recent first, once each', () async {
    final store = MemoryStore();
    final container = testContainer(FakeBackend(), store: store);
    await sessionOf(container);
    await container.read(recentSearchesProvider.future);
    final recent = container.read(recentSearchesProvider.notifier);

    await recent.add(const RecentSearch.place(rivoli));
    await recent.add(const RecentSearch.line(metro1));
    await recent.add(const RecentSearch.place(rivoli));
    for (var i = 0; i < 10; i++) {
      await recent.add(RecentSearch.line(LineSummary(id: 'C$i', mode: TransportMode.bus)));
    }

    final searches = container.read(recentSearchesProvider).value!;
    expect(searches, hasLength(10));
    expect(searches.first.key, 'line:C9');
    expect(searches.map((search) => search.key), isNot(contains('place:${rivoli.id}')));
    expect((await store.readJson('recent_searches') as List), hasLength(10));
  });

  test('reads them back, skipping entries it no longer understands', () async {
    final store = MemoryStore({
      'recent_searches': [
        {'place': rivoli.toJson()},
        {'line': {'id': 'C01371'}},
        {'something': 'else'},
        'not a map',
        {'line': metro1.toJson()},
      ],
    });
    final container = testContainer(FakeBackend(), store: store);
    await sessionOf(container);

    final searches = await container.read(recentSearchesProvider.future);

    expect(searches.map((search) => search.key), ['place:${rivoli.id}', 'line:C01371']);
  });

  test('clears them', () async {
    final store = MemoryStore({
      'recent_searches': [
        {'line': metro1.toJson()},
      ],
    });
    final container = testContainer(FakeBackend(), store: store);
    await sessionOf(container);
    await container.read(recentSearchesProvider.future);

    await container.read(recentSearchesProvider.notifier).clear();

    expect(container.read(recentSearchesProvider).value, isEmpty);
    expect(store.values, isEmpty);
  });
}
