// The device's compass on a real phone (skipped without one, e.g. the Linux app of the CI):
// flutter test integration_test/device_heading_test.dart -d <android device>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:website_app/core/location/device_heading.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the compass gives headings', (tester) async {
    final headings = deviceHeadings();
    if (headings == null) {
      markTestSkipped('No compass here');
      return;
    }

    final received = await tester.runAsync(() => headings.take(10).toList().timeout(const Duration(seconds: 10)));

    expect(received, hasLength(10));
    expect(received!.every((heading) => heading >= 0 && heading < 360), isTrue);
    // ignore: avoid_print
    print('Headings: ${received.map((heading) => heading.round()).join(', ')}');
  });
}
