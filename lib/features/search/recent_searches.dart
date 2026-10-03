import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_controller.dart';

/// A place or a line chosen in the search, kept on this device only
class RecentSearch {
  const RecentSearch.place(PlaceResult this.place) : line = null;

  const RecentSearch.line(LineSummary this.line) : place = null;

  final PlaceResult? place;
  final LineSummary? line;

  String get key => place != null ? 'place:${place!.id}' : 'line:${line!.id}';

  Map<String, dynamic> toJson() => {if (place != null) 'place': place!.toJson(), if (line != null) 'line': line!.toJson()};

  static RecentSearch? fromJson(Map<String, dynamic> json) {
    if (json['place'] is Map<String, dynamic>) {
      return RecentSearch.place(PlaceResult.fromJson(json['place'] as Map<String, dynamic>));
    }
    if (json['line'] is Map<String, dynamic>) {
      return RecentSearch.line(LineSummary.fromJson(json['line'] as Map<String, dynamic>));
    }
    return null;
  }
}

/// Last places and lines chosen in the search, most recent first
class RecentSearches extends AsyncNotifier<List<RecentSearch>> {
  static const _key = 'recent_searches';
  static const _max = 10;

  @override
  Future<List<RecentSearch>> build() async {
    // Reloaded when the account changes (the device copy is cleared at sign-in / sign-out)
    ref.watch(authControllerProvider);
    final json = await ref.read(localStoreProvider).readJson(_key);
    if (json is! List) {
      return const [];
    }
    return [
      for (final item in json)
        if (item is Map<String, dynamic>) ?_tryParse(item),
    ];
  }

  static RecentSearch? _tryParse(Map<String, dynamic> json) {
    try {
      return RecentSearch.fromJson(json);
    } catch (_) {
      // Model changed since it was saved
      return null;
    }
  }

  Future<void> add(RecentSearch search) async {
    final next = [search, ...?state.value?.where((item) => item.key != search.key)].take(_max).toList();
    state = AsyncData(next);
    await ref.read(localStoreProvider).writeJson(_key, next.map((item) => item.toJson()).toList());
  }

  Future<void> clear() async {
    state = const AsyncData([]);
    await ref.read(localStoreProvider).remove(_key);
  }
}

final recentSearchesProvider = AsyncNotifierProvider<RecentSearches, List<RecentSearch>>(RecentSearches.new);
