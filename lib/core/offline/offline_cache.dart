import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';

/// When the app last fell back on cached data because the server could not be reached; null while online
class OfflineState extends Notifier<DateTime?> {
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
final offlineProvider = NotifierProvider<OfflineState, DateTime?>(OfflineState.new);

/// Light offline mode: the last answers of the read endpoints (stops, lines, timetables, favorites, traffic,
/// journeys…) are kept on the device, and served when the server can't be reached. Real-time-only endpoints
/// (vehicles, departures of a ride, Vélib, search) are not kept: stale data there would mislead.
class OfflineCacheInterceptor extends Interceptor {
  OfflineCacheInterceptor({required this.store, required this.onOffline, required this.onOnline});

  final LocalStore store;
  final void Function(DateTime dataAt) onOffline;
  final void Function() onOnline;

  static const _prefix = 'http_cache:';
  static const _indexKey = 'http_cache_index';

  /// Answers kept, most recent first
  static const _maxEntries = 60;

  /// Bigger answers are not kept (localStorage holds about 5 MB on the web)
  static const _maxLength = 300000;

  static final _excluded = RegExp(r'/(vehicles|rides|bikes|search)\b|^/api/v2/me(/export)?$');

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

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    onOnline();
    if (_cacheable(response.requestOptions) && response.statusCode == 200 && response.data != null) {
      _save(_key(response.requestOptions), response.data);
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // No answer at all: network down or server unreachable
    if (err.response == null && _cacheable(err.requestOptions)) {
      final cached = await store.readJson(_key(err.requestOptions));
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

  Future<void> _save(String key, Object data) async {
    if (jsonEncode(data).length > _maxLength) {
      return;
    }
    await store.writeJson(key, {'at': DateTime.now().toIso8601String(), 'data': data});
    final index = await store.readJson(_indexKey);
    final keys = [key, ...(index is List ? index.map((item) => '$item').where((item) => item != key) : const <String>[])];
    for (final old in keys.skip(_maxEntries)) {
      await store.remove(old);
    }
    await store.writeJson(_indexKey, keys.take(_maxEntries).toList());
  }
}
