import 'dart:convert';

import 'package:website_app/core/storage/local_store.dart';

/// [LocalStore] in memory (no platform plugin in the tests)
class MemoryStore implements LocalStore {
  MemoryStore([Map<String, Object?>? initial]) {
    initial?.forEach(writeJson);
  }

  /// Stored documents, as JSON text like the real store
  final values = <String, String>{};

  @override
  Future<Object?> readJson(String key) async => values[key] == null ? null : jsonDecode(values[key]!);

  @override
  Future<void> writeJson(String key, Object? value) async => values[key] = jsonEncode(value);

  @override
  Future<void> remove(String key) async => values.remove(key);
}
