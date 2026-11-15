import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/refresh.dart';
import '../../l10n/l10n.dart';

const _storageKey = 'remote_config';

/// What the backend tells the apps (`/api/v2/app-config`, without a token): asked at start-up and every hour while the
/// app is on screen, kept on the device for the starts when the server can't be reached (a version too old stays so
/// offline); nothing known: nothing required, nothing switched off.
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  ref.refreshEvery(const Duration(hours: 1));
  final store = ref.watch(localStoreProvider);
  try {
    final dio = ref.watch(dioFactoryProvider)()..options.headers.addAll(AppConfig.clientHeaders);
    final response = await dio.get<Map<String, dynamic>>('/api/v2/app-config');
    final config = RemoteConfig.fromJson(response.data!);
    unawaited(store.writeJson(_storageKey, config.toJson()));
    return config;
  } catch (e) {
    debugPrint('App config unavailable: $e');
    final kept = await store.readJson(_storageKey);
    try {
      return kept is Map<String, dynamic> ? RemoteConfig.fromJson(kept) : const RemoteConfig();
    } catch (_) {
      return const RemoteConfig();
    }
  }
});

/// The build's version (`0.14.0`, `0.14.0-12`; empty for a development build), replaced in the tests
final appVersionProvider = Provider<String>((ref) => AppConfig.version);

/// `X.Y.Z` at the start of [version] as numbers, null when it has none (a development build)
List<int>? _numbers(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  return match == null ? null : [for (var group = 1; group <= 3; group++) int.parse(match.group(group)!)];
}

/// Whether [version] (`0.14.0`, or `0.14.0-12` twelve commits after it) is older than [minimum] (`X.Y.Z`). A version
/// or a minimum that can't be read is never too old: development builds, a mistake in the server's configuration.
bool isOlderThan(String version, String? minimum) {
  final own = _numbers(version);
  final least = minimum == null ? null : _numbers(minimum);
  if (own == null || least == null) {
    return false;
  }
  for (var index = 0; index < 3; index++) {
    if (own[index] != least[index]) {
      return own[index] < least[index];
    }
  }
  return false;
}

/// The backend no longer supports this version on this platform: the app asks to be updated instead of showing pages
/// that would fail
final updateRequiredProvider = Provider<bool>((ref) {
  final minimum = ref.watch(remoteConfigProvider).value?.minVersions[AppConfig.platform];
  return isOlderThan(ref.watch(appVersionProvider), minimum);
});

/// Whether the backend switched a feature off (`vehicles`): the app then doesn't ask for it
final featureDisabledProvider = Provider.family<bool, String>(
  (ref, feature) => ref.watch(remoteConfigProvider).value?.disabledFeatures.contains(feature) ?? false,
);

/// The message for everyone in the app's language, else in French, else whatever there is; null without one
final remoteNoticeProvider = Provider<String?>((ref) {
  final notice = ref.watch(remoteConfigProvider).value?.notice ?? const <String, String>{};
  final text = notice[ref.watch(localeProvider).languageCode] ?? notice['fr'] ?? notice.values.firstOrNull;
  return text == null || text.trim().isEmpty ? null : text.trim();
});
