import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_providers.dart';
import 'package:website_app/core/config.dart';
import 'package:website_app/core/storage/local_store.dart';
import 'package:website_app/features/auth/auth_controller.dart';

import 'fake_backend.dart';
import 'memory_store.dart';

/// Key of the refresh token in the secure storage (a stored one = signed in)
final refreshTokenKey = '${AppConfig.storagePrefix}refresh_token';

/// Providers on [backend] and [store], signed in when [refreshToken] is given. Disposed after the test.
ProviderContainer testContainer(FakeBackend backend, {MemoryStore? store, String? refreshToken, List<Override> overrides = const []}) {
  FlutterSecureStorage.setMockInitialValues({refreshTokenKey: ?refreshToken});
  backend.post('/api/auth/guest', {'jwt': 'guest-token', 'expiresIn': 2592000});
  backend.post('/api/token/refresh', {'jwt': 'access-token', 'refreshToken': 'next-refresh-token', 'expiresIn': 3600});
  final container = ProviderContainer(overrides: [
    dioFactoryProvider.overrideWithValue(backend.dio),
    localStoreProvider.overrideWithValue(store ?? MemoryStore()),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Waits until the session is read from the storage
Future<AuthStatus> sessionOf(ProviderContainer container) async {
  container.listen(authControllerProvider, (_, _) {});
  for (var i = 0; i < 100 && container.read(authControllerProvider) == AuthStatus.unknown; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(authControllerProvider);
}
