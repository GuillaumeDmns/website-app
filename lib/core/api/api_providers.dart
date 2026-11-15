import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../auth/token_store.dart';
import '../config.dart';
import '../offline/offline_cache.dart';
import 'auth_api.dart';
import 'auth_interceptor.dart';
import 'mobility_api.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// New clients of the backend (the tests give them a fake backend)
final dioFactoryProvider = Provider<Dio Function()>((ref) => () => Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    )));

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioFactoryProvider)()..options.headers.addAll(AppConfig.clientHeaders)));

/// Authenticated client
final apiDioProvider = Provider<Dio>((ref) {
  final dio = ref.watch(dioFactoryProvider)()..options.headers.addAll(AppConfig.clientHeaders);
  dio.interceptors.add(AuthInterceptor(
    tokenStore: ref.watch(tokenStoreProvider),
    authApi: ref.watch(authApiProvider),
    dio: dio,
    onSessionLost: () => ref.read(authControllerProvider.notifier).onSessionLost(),
  ));
  dio.interceptors.add(ref.watch(offlineCacheProvider));
  return dio;
});

final mobilityApiProvider = Provider<MobilityApi>((ref) => MobilityApi(ref.watch(apiDioProvider)));

extension CancellableApi on Ref {
  /// The API for what this provider reads itself: its requests still on their way are given up when it is disposed
  /// or built again (the page left, the text typed further, the map moved), instead of going on to the end for
  /// nobody, on the device's network and the backend's quotas
  MobilityApi get mobilityApi {
    final cancelToken = CancelToken();
    onDispose(cancelToken.cancel);
    return watch(mobilityApiProvider).cancelledWith(cancelToken);
  }
}
