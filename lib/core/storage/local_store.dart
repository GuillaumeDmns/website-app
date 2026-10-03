import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON documents kept on the device (cache of the favorites, recent searches). Works on every platform
/// (localStorage on the web). Failures are ignored: it is only a cache.
class LocalStore {
  LocalStore([SharedPreferencesAsync? preferences]) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<Object?> readJson(String key) async {
    try {
      final value = await _preferences.getString(key);
      return value == null ? null : jsonDecode(value);
    } catch (e) {
      debugPrint('LocalStore read $key failed: $e');
      return null;
    }
  }

  Future<void> writeJson(String key, Object value) async {
    try {
      await _preferences.setString(key, jsonEncode(value));
    } catch (e) {
      debugPrint('LocalStore write $key failed: $e');
    }
  }

  Future<void> remove(String key) async {
    try {
      await _preferences.remove(key);
    } catch (e) {
      debugPrint('LocalStore remove $key failed: $e');
    }
  }
}

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());
