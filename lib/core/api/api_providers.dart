import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../auth/token_store.dart';
import '../config.dart';
import '../offline/offline_cache.dart';
import '../storage/local_store.dart';
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

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioFactoryProvider)()));

/// Authenticated client
final apiDioProvider = Provider<Dio>((ref) {
  final dio = ref.watch(dioFactoryProvider)();
  dio.interceptors.add(AuthInterceptor(
    tokenStore: ref.watch(tokenStoreProvider),
    authApi: ref.watch(authApiProvider),
    dio: dio,
    onSessionLost: () => ref.read(authControllerProvider.notifier).onSessionLost(),
  ));
  dio.interceptors.add(OfflineCacheInterceptor(
    store: ref.watch(localStoreProvider),
    onOffline: (at) => ref.read(offlineProvider.notifier).offline(at),
    onOnline: () => ref.read(offlineProvider.notifier).online(),
  ));
  return dio;
});

final mobilityApiProvider = Provider<MobilityApi>((ref) => MobilityApi(ref.watch(apiDioProvider)));
