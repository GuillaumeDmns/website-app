import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_providers.dart';

import '../../support/fake_backend.dart';
import '../../support/test_container.dart';

void main() {
  test("every request tells the app's platform and version, for the backend's anonymous device counts", () async {
    FlutterSecureStorage.setMockInitialValues({});
    final backend = FakeBackend();
    backend.post('/api/auth/guest', {'jwt': 'guest-1', 'expiresIn': 2592000});
    backend.get('/api/v2/traffic', []);
    final container = testContainer(backend);
    addTearDown(container.dispose);

    await container.read(apiDioProvider).get<Object>('/api/v2/traffic');

    for (final request in [backend.requestsTo('/api/auth/guest').single, backend.requestsTo('/api/v2/traffic').single]) {
      // A test build: no version from git, the platform of the tests
      expect(request.headers['X-App-Version'], 'dev');
      expect(request.headers['X-App-Platform'], 'android');
    }
  });
}
