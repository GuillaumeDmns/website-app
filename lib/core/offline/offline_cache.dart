import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_shown.dart';
import '../storage/local_store.dart';

/// When the app last fell back on cached data because the server could not be reached; null while online
class OfflineController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void offline(DateTime dataAt) {
    if (state == null || dataAt.isBefore(state!)) {
      state = dataAt;
    }
  }

  void online() {
    if (state != null) {
      state = null;
    }
  }
}

/// Oldest cached data shown since the server stopped answering, null when online
final offlineProvider = NotifierProvider<OfflineController, DateTime?>(OfflineController.new);

/// Light offline mode: the last answers of the read endpoints (stops, lines, timetables, favorites, traffic,
/// journeys…) are kept on the device, and served when the server can't be reached. Real-time-only endpoints
/// (vehicles, departures of a ride, Vélib, search, addresses of a point) are not kept: stale data there would mislead;
/// nor the stops of the part of the map shown, a new answer at each move of the map.
class OfflineCacheInterceptor extends Interceptor {
  OfflineCacheInterceptor({
    required this.store,
    required this.onOffline,
    required this.onOnline,
    this.flushAfter = const Duration(minutes: 5),
  });

  /// The answers wait in memory at most this long before they are written to the device
  final Duration flushAfter;

  final LocalStore store;
  final void Function(DateTime dataAt) onOffline;
  final void Function() onOnline;

  static const _prefix = 'http_cache:';
  static const _indexKey = 'http_cache_index';

  /// Answers kept, most recent first
  static const _maxEntries = 60;

  /// Bigger answers are not kept (localStorage holds about 5 MB on the web)
  static const _maxLength = 300000;

  static final _excluded = RegExp(r'/(vehicles|rides|bikes|search|reverse)\b|^/api/v2/nearby$|^/api/v2/me(/export|/api-tokens)?$');

  static bool _cacheable(RequestOptions options) =>
      options.method == 'GET' && options.path.startsWith('/api/v2/') && !_excluded.hasMatch(options.path);

  static String _key(RequestOptions options) => '$_prefix${options.uri.path}?${options.uri.query}';

  /// Every cached answer (sign-out: another account must not see them)
  static Future<void> clear(LocalStore store) async {
    final index = await store.readJson(_indexKey);
    if (index is List) {
      for (final key in index) {
        await store.remove('$key');
      }
    }
    await store.remove(_indexKey);
  }

  /// The answers not written to the device yet, the latest of each request, oldest first. The device's store writes
  /// its whole file again at each change (Android's DataStore) and keeps it all in memory: writing each answer as it
  /// came, with the index, rewrote it several times every 30 s on the home page. They are written together when the
  /// app leaves the screen ([flush], `offlineCacheProvider`), and after [flushAfter] at the latest.
  final _pending = <String, ({DateTime at, Object data})>{};
  Timer? _flushTimer;

  /// Writes one batch at a time: each one rewrites the index, two at once would lose entries (never cleared then)
  Future<void> _saving = Future.value();

  /// Writes the answers waiting in memory to the device
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) {
      return _saving;
    }
    final entries = Map.of(_pending);
    _pending.clear();
    return _saving = _saving.then((_) => _save(entries));
  }

  /// Every answer kept, written or not (sign-in, sign-out: another account must not see them)
  Future<void> clearAll() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    return _saving = _saving.then((_) => clear(store));
  }

  /// The app closes: what waits is written, nothing is kept for later
  void dispose() {
    flush();
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    onOnline();
    final data = response.data;
    if (_cacheable(response.requestOptions) && response.statusCode == 200 && data != null) {
      // The latest one last
      final key = _key(response.requestOptions);
      _pending.remove(key);
      _pending[key] = (at: DateTime.now(), data: data);
      _flushTimer ??= Timer(flushAfter, flush);
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // No answer at all: network down or server unreachable (not a request given up by the app itself)
    if (err.response == null && err.type != DioExceptionType.cancel && _cacheable(err.requestOptions)) {
      final waiting = _pending[_key(err.requestOptions)];
      final cached = waiting != null
          ? {'at': waiting.at.toIso8601String(), 'data': waiting.data}
          : await store.readJson(_key(err.requestOptions));
      if (cached is Map<String, dynamic> && cached['data'] != null) {
        final at = DateTime.tryParse(cached['at'] as String? ?? '') ?? DateTime.now();
        onOffline(at);
        return handler.resolve(Response<dynamic>(
          requestOptions: err.requestOptions,
          data: cached['data'],
          statusCode: 200,
          extra: {'offlineAt': at},
        ));
      }
      onOffline(DateTime.now());
    }
    handler.next(err);
  }

  Future<void> _save(Map<String, ({DateTime at, Object data})> entries) async {
    final written = <String>[];
    for (final MapEntry(:key, :value) in entries.entries) {
      final entry = jsonEncode({'at': value.at.toIso8601String(), 'data': value.data});
      if (entry.length <= _maxLength) {
        await store.writeEncoded(key, entry);
        written.add(key);
      }
    }
    if (written.isEmpty) {
      return;
    }
    final index = await store.readJson(_indexKey);
    final keys = [
      ...written.reversed,
      ...(index is List ? index.map((item) => '$item').where((item) => !written.contains(item)) : const <String>[]),
    ];
    for (final old in keys.skip(_maxEntries)) {
      await store.remove(old);
    }
    await store.writeJson(_indexKey, keys.take(_maxEntries).toList());
  }
}

/// The app's offline cache: its answers are written when the app leaves the screen (screen off, another app, a tab
/// hidden), where a process may be stopped without notice
final offlineCacheProvider = Provider<OfflineCacheInterceptor>((ref) {
  final cache = OfflineCacheInterceptor(
    store: ref.watch(localStoreProvider),
    onOffline: (at) => ref.read(offlineProvider.notifier).offline(at),
    onOnline: () => ref.read(offlineProvider.notifier).online(),
  );
  ref.listen(appShownProvider, (_, shown) {
    if (!shown) {
      cache.flush();
    }
  });
  ref.onDispose(cache.dispose);
  return cache;
});
