import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_exception.dart';
import 'package:website_app/core/api/api_providers.dart';
import 'package:website_app/features/auth/auth_controller.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/memory_store.dart';
import '../../support/test_container.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  test('starts as a guest without refresh token, signed in with one', () async {
    expect(await sessionOf(testContainer(backend)), AuthStatus.guest);
    expect(await sessionOf(testContainer(backend, refreshToken: 'stored')), AuthStatus.signedIn);
  });

  test('signs in with a password, keeping what the guest saved', () async {
    final store = MemoryStore({'favorites': [], 'recent_searches': [], 'http_cache_index': ['http_cache:/api/v2/traffic?'], 'http_cache:/api/v2/traffic?': {}});
    final container = testContainer(backend, store: store);
    await sessionOf(container);
    backend.post('/api/signin', {'jwt': 'jwt', 'refreshToken': 'refresh', 'expiresIn': 3600});

    await container.read(authControllerProvider.notifier).signIn(' ada ', 'secret');

    expect(container.read(authControllerProvider), AuthStatus.signedIn);
    expect(backend.requestsTo('/api/signin').single.data, {'username': 'ada', 'password': 'secret'});
    expect(container.read(tokenStoreProvider).accessToken, 'jwt');
    // The guest's favorites and searches stay; the cached answers of the guest go
    expect(store.values.keys, containsAll(['favorites', 'recent_searches']));
    expect(store.values.keys.where((key) => key.startsWith('http_cache')), isEmpty);
  });

  test('says when the password is wrong', () async {
    final container = testContainer(backend);
    await sessionOf(container);
    backend.post('/api/signin', null, status: 401);

    await expectLater(container.read(authControllerProvider.notifier).signIn('ada', 'wrong'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', currentL10n.authWrongCredentials)));
    expect(container.read(authControllerProvider), AuthStatus.guest);
  });

  test('translates the sign-up refusals', () async {
    final container = testContainer(backend);
    await sessionOf(container);
    backend.post('/api/signup', {'status': 409, 'detail': 'Username already used'}, status: 409);

    await expectLater(container.read(authControllerProvider.notifier).signUp('ada', 'ada@example.com', 'correct horse'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', currentL10n.authUsernameTaken)));
  });

  test('signs in with Google', () async {
    final container = testContainer(backend);
    await sessionOf(container);
    backend.post('/api/auth/google', {'jwt': 'jwt', 'refreshToken': 'refresh', 'expiresIn': 3600});

    await container.read(authControllerProvider.notifier).signInWithGoogle('google-id-token');

    expect(backend.requestsTo('/api/auth/google').single.data, {'idToken': 'google-id-token'});
    expect(container.read(authControllerProvider), AuthStatus.signedIn);
  });

  test('signs out: the server forgets the session, the device the account', () async {
    final store = MemoryStore({'favorites': [], 'recent_searches': [], 'go_session': {}, 'journey_preferences': {}, 'locale': 'fr'});
    final container = testContainer(backend, store: store, refreshToken: 'stored');
    await sessionOf(container);
    backend.post('/api/logout', null, status: 204);

    await container.read(authControllerProvider.notifier).signOut();

    expect(backend.requestsTo('/api/logout').single.data, {'refreshToken': 'stored'});
    expect(container.read(authControllerProvider), AuthStatus.guest);
    expect(container.read(tokenStoreProvider).signedIn, isFalse);
    expect(store.values.keys, ['locale']);
  });

  test('deletes the account, then carries on as a guest', () async {
    final store = MemoryStore({'favorites': []});
    final container = testContainer(backend, store: store, refreshToken: 'stored');
    await sessionOf(container);
    backend.delete('/api/v2/me');

    await container.read(authControllerProvider.notifier).deleteAccount();

    expect(backend.requestsTo('/api/v2/me', method: 'DELETE'), hasLength(1));
    expect(container.read(authControllerProvider), AuthStatus.guest);
    expect(store.values, isEmpty);
  });

  test('a lost session goes back to guest', () async {
    final store = MemoryStore({'favorites': []});
    final container = testContainer(backend, store: store, refreshToken: 'stored');
    await sessionOf(container);

    await container.read(authControllerProvider.notifier).onSessionLost();

    expect(container.read(authControllerProvider), AuthStatus.guest);
    expect(store.values, isEmpty);
  });
}
