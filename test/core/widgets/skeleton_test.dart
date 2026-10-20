import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/widgets/async_view.dart';
import 'package:website_app/core/widgets/skeleton.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  Widget app(Widget child, {List<DateTime> clock = const []}) => ProviderScope(
        overrides: [if (clock.isNotEmpty) nowProvider.overrideWith((ref) => Stream.fromIterable(clock))],
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('loading the first time shows grey cards, not a spinner', (tester) async {
    await tester.pumpWidget(app(AsyncView<int>(value: const AsyncValue.loading(), data: (value) => Text('$value'))));

    expect(find.byType(SkeletonCards), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel(currentL10n.loading), findsOneWidget);
  });

  testWidgets('tells how fresh the data is', (tester) async {
    final clock = StreamController<DateTime>();
    addTearDown(clock.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [nowProvider.overrideWith((ref) => clock.stream)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: const Scaffold(body: UpdatedAgo<int>(value: AsyncValue.data(1))),
      ),
    ));
    clock.add(DateTime.now());
    await tester.pump();
    expect(find.text(currentL10n.updatedJustNow), findsOneWidget);

    clock.add(DateTime.now().add(const Duration(seconds: 45)));
    // The clock's new time reaches the widget a frame later
    await tester.pump();
    await tester.pump();
    expect(find.text(currentL10n.updatedSecondsAgo(40)), findsOneWidget);
  });
}
