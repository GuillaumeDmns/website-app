import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/utils/refresh.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // The app on screen
  setUp(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  var shown = true;

  /// Screen off or back on, through the states the system goes through
  void screen({required bool on}) {
    if (on == shown) {
      return;
    }
    shown = on;
    for (final lifecycle in on
        ? [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]
        : [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(lifecycle);
    }
  }

  tearDown(() => screen(on: true));

  /// A provider fetched every minute, counting its fetches
  ({ProviderContainer container, FutureProvider<int> provider, int Function() fetches}) minutely({
    bool whileFollowed = false,
    bool reloadWhenHidden = false,
  }) {
    var fetches = 0;
    final provider = FutureProvider.autoDispose<int>((ref) async {
      ref.refreshEvery(const Duration(minutes: 1), whileFollowed: whileFollowed, reloadWhenHidden: reloadWhenHidden);
      return ++fetches;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
    return (container: container, provider: provider, fetches: () => fetches);
  }

  testWidgets('fetched again each period on screen', (tester) async {
    final data = minutely();
    await tester.pump(const Duration(minutes: 3, seconds: 5));
    expect(data.fetches(), 4);
  });

  testWidgets('nothing fetched off screen, once when back', (tester) async {
    final data = minutely();
    await tester.pump(const Duration(seconds: 5));
    screen(on: false);
    await tester.pump(const Duration(hours: 1));
    expect(data.fetches(), 1);

    screen(on: true);
    await tester.pump(const Duration(seconds: 5));
    expect(data.fetches(), 2);
    // And on from there
    await tester.pump(const Duration(minutes: 1));
    expect(data.fetches(), 3);
  });

  testWidgets('back on screen before the period ends: nothing fetched early', (tester) async {
    final data = minutely();
    screen(on: false);
    await tester.pump(const Duration(seconds: 20));
    screen(on: true);
    await tester.pump(const Duration(seconds: 20));
    expect(data.fetches(), 1);
    await tester.pump(const Duration(seconds: 25));
    expect(data.fetches(), 2);
  });

  testWidgets('what GO follows goes on off screen, only while it follows', (tester) async {
    final followed = minutely(whileFollowed: true);
    final other = minutely();
    // Each has its own container: both told that GO follows
    followed.container.read(followedOffScreenProvider.notifier).set(true);
    other.container.read(followedOffScreenProvider.notifier).set(true);
    screen(on: false);
    await tester.pump(const Duration(minutes: 3, seconds: 5));
    expect(followed.fetches(), 4);
    expect(other.fetches(), 1);

    followed.container.read(followedOffScreenProvider.notifier).set(false);
    await tester.pump(const Duration(minutes: 10));
    expect(followed.fetches(), 4);
  });

  testWidgets('a period ended off screen while followed again: fetched then', (tester) async {
    final data = minutely(whileFollowed: true);
    screen(on: false);
    await tester.pump(const Duration(minutes: 2));
    expect(data.fetches(), 1);
    data.container.read(followedOffScreenProvider.notifier).set(true);
    await tester.pump(const Duration(seconds: 1));
    expect(data.fetches(), 2);
  });

  testWidgets('outdated data is reloaded when back, for its readers not to show it', (tester) async {
    final data = minutely(reloadWhenHidden: true);
    await tester.pump(const Duration(seconds: 1));
    screen(on: false);
    await tester.pump(const Duration(minutes: 5));
    screen(on: true);
    expect(data.container.read(data.provider).isReloading, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(data.container.read(data.provider).value, 2);
  });

  testWidgets('a clock ticks on screen only', (tester) async {
    final ticking = <DateTime>[];
    final hidden = <DateTime>[];
    final subscriptions = [
      clockEvery(const Duration(seconds: 15), shown: true).listen(ticking.add),
      clockEvery(const Duration(seconds: 15), shown: false).listen(hidden.add),
    ];
    await tester.pump(const Duration(minutes: 1));
    expect(ticking, hasLength(5));
    expect(hidden, hasLength(1));
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  });
}
