import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/features/remote_config/remote_config.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/memory_store.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a version is too old below the minimum, whatever follows its three numbers', () {
    expect(isOlderThan('0.13.2', '0.14.0'), isTrue);
    expect(isOlderThan('0.9.0', '0.14.0'), isTrue);
    expect(isOlderThan('0.14.0', '0.14.0'), isFalse);
    expect(isOlderThan('0.14.0-12', '0.14.0'), isFalse);
    expect(isOlderThan('0.13.9-40', '0.14.0'), isTrue);
    expect(isOlderThan('1.0.0', '0.99.99'), isFalse);
  });

  test('a development build, a platform without minimum or an unreadable minimum are never too old', () {
    expect(isOlderThan('', '0.14.0'), isFalse);
    expect(isOlderThan('dev', '0.14.0'), isFalse);
    expect(isOlderThan('0.1.0', null), isFalse);
    expect(isOlderThan('0.1.0', 'latest'), isFalse);
  });

  test('asked without a token, kept on the device', () async {
    final backend = standardBackend()
      ..get('/api/v2/app-config', const RemoteConfig(minVersions: {'android': '1.0.0'}, disabledFeatures: ['vehicles']).toJson());
    final store = MemoryStore();
    final container = testContainer(backend, store: store, overrides: [appVersionProvider.overrideWithValue('0.14.0')]);

    final config = await container.read(remoteConfigProvider.future);
    expect(config.minVersions, {'android': '1.0.0'});
    expect(backend.requestsTo('/api/v2/app-config').single.headers.containsKey('Authorization'), isFalse);
    // Tests run as Android
    expect(container.read(updateRequiredProvider), isTrue);
    expect(container.read(featureDisabledProvider('vehicles')), isTrue);
    expect(container.read(featureDisabledProvider('journeys')), isFalse);
    await pumpEventQueue();
    expect(await store.readJson('remote_config'), isNotNull);
  });

  test('server out of reach: what it said last, nothing required the first time', () async {
    final backend = standardBackend()..down = true;
    final first = testContainer(backend, overrides: [appVersionProvider.overrideWithValue('0.14.0')]);
    expect(await first.read(remoteConfigProvider.future), const RemoteConfig());
    expect(first.read(updateRequiredProvider), isFalse);

    final store = MemoryStore({'remote_config': const RemoteConfig(minVersions: {'android': '1.0.0'}).toJson()});
    final later = testContainer(backend, store: store, overrides: [appVersionProvider.overrideWithValue('0.14.0')]);
    await later.read(remoteConfigProvider.future);
    expect(later.read(updateRequiredProvider), isTrue);
  });

  test('the message in the app language, else in French, none when empty', () async {
    Future<String?> notice(Map<String, String> texts, Locale locale) async {
      final backend = standardBackend()..get('/api/v2/app-config', RemoteConfig(notice: texts).toJson());
      final container = testContainer(backend, overrides: [localeProvider.overrideWith(() => LocaleController(locale))]);
      await container.read(remoteConfigProvider.future);
      return container.read(remoteNoticeProvider);
    }

    expect(await notice({'fr': 'Grève mardi', 'en': 'Strike on Tuesday'}, const Locale('en')), 'Strike on Tuesday');
    expect(await notice({'fr': 'Grève mardi'}, const Locale('en')), 'Grève mardi');
    expect(await notice({}, const Locale('fr')), isNull);
    expect(await notice({'fr': '  '}, const Locale('fr')), isNull);
  });

  test('vehicles switched off: none, and none asked', () async {
    final backend = standardBackend()..get('/api/v2/app-config', const RemoteConfig(disabledFeatures: ['vehicles']).toJson());
    final container = testContainer(backend);
    await container.read(remoteConfigProvider.future);
    container.listen(lineVehiclesProvider('C01371'), (_, _) {});

    expect((await container.read(lineVehiclesProvider('C01371').future)).vehicles, isEmpty);
    expect(backend.requestsTo('/api/v2/lines/C01371/vehicles'), isEmpty);
  });
}
