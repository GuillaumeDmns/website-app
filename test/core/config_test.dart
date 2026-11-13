import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/config.dart';

void main() {
  test('the prod and beta flavors use the production backend, the others the development one', () {
    expect(AppConfig.environmentOfFlavor('prod'), AppEnvironment.prod);
    expect(AppConfig.environmentOfFlavor('beta'), AppEnvironment.prod);
    expect(AppConfig.environmentOfFlavor('dev'), AppEnvironment.dev);
    expect(AppConfig.environmentOfFlavor(null), AppEnvironment.dev);
  });

  test('a build without the beta flavor is not the beta app', () {
    // flutter test runs without a flavor
    expect(AppConfig.isBeta, isFalse);
  });
}
