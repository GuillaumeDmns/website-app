import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../auth/token_store.dart';
import '../config.dart';
import 'auth_api.dart';
import 'auth_interceptor.dart';
import 'mobility_api.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

Dio _baseDio() => Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(_baseDio()));

/// Authenticated client
final apiDioProvider = Provider<Dio>((ref) {
  final dio = _baseDio();
  dio.interceptors.add(AuthInterceptor(
    tokenStore: ref.watch(tokenStoreProvider),
    authApi: ref.watch(authApiProvider),
    dio: dio,
    onSessionLost: () => ref.read(authControllerProvider.notifier).onSessionLost(),
  ));
  return dio;
});

final mobilityApiProvider = Provider<MobilityApi>((ref) => MobilityApi(ref.watch(apiDioProvider)));
