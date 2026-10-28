import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/app/sheet_sizes.dart';

void main() {
  const screen = Size(412, 915);
  SheetSizes sizesOf(String location, {double? fitted}) => sheetSizes(location, screen: screen, topInset: 40, fitted: fitted);

  test('each page its sizes: half the screen, a higher peek for the journey search, never under the status bar', () {
    final home = sizesOf(Routes.home);
    expect(home.middle, 0.5);
    expect(home.min, closeTo(110 / 915, 1e-9));
    expect(home.max, closeTo(875 / 915, 1e-9));
    expect(home.locked, isFalse);
    expect(sizesOf('/journey?from=here&to=IDFM:70003').min, closeTo(150 / 915, 1e-9));
    // A stop: its departures at once
    expect(sizesOf('/stops/IDFM%3A70001').middle, 0.62);
    expect(sizesOf('/stops/IDFM%3A70001/timetable').middle, 0.5);
    // Search: locked at its highest
    final search = sizesOf(Routes.search);
    expect((search.min, search.middle, search.locked), (search.max, search.max, true));
  });

  test("GO's sheet fits its content, the map keeping half of the screen at least", () {
    expect(sizesOf(Routes.go).middle, 0.4);
    expect(sizesOf(Routes.go, fitted: 300).middle, closeTo(322 / 915, 1e-9));
    expect(sizesOf(Routes.go, fitted: 800).middle, 0.5);
    expect(sizesOf(Routes.go, fitted: 10).middle, closeTo(sizesOf(Routes.go).min, 1e-9));
  });

  test('a new page opens at its middle; back, the page below as it was left', () {
    final history = SheetHistory(Routes.home);
    final stop = sizesOf('/stops/IDFM:70001');

    // The home page raised to its highest, a stop opened from it: at its middle, the map showing the stop
    expect(history.change(Routes.home, '/stops/IDFM:70001', size: 0.95, sizes: stop), stop.middle);
    // Lowered on the stop page, then a line from it
    expect(history.change('/stops/IDFM:70001', '/lines/C01371', size: 0.2, sizes: sizesOf('/lines/C01371')), 0.5);
    // Back: the stop lowered, then the home page raised, as they were left
    expect(history.change('/lines/C01371', '/stops/IDFM:70001', size: 0.5, sizes: stop), 0.2);
    expect(history.change('/stops/IDFM:70001', Routes.home, size: 0.2, sizes: sizesOf(Routes.home)), 0.95);
    // Opened again later: its middle, not the height it had
    expect(history.change(Routes.home, '/stops/IDFM:70001', size: 0.95, sizes: stop), stop.middle);
  });

  test('the same page with other parameters keeps the sheet where it is, within its sizes', () {
    final history = SheetHistory('/journey?from=here&to=IDFM:70003');
    final journey = sizesOf('/journey?from=here&to=IDFM:70003');

    expect(history.change('/journey?from=here&to=IDFM:70003', '/journey?from=here&to=IDFM:70003&at=2026-10-28T08:00',
        size: 0.8, sizes: journey), isNull);
    // Then a new page from it, and back to the page as changed
    history.change('/journey?from=here&to=IDFM:70003&at=2026-10-28T08:00', '/journey/detail', size: 0.8, sizes: sizesOf('/journey/detail'));
    expect(history.change('/journey/detail', '/journey?from=here&to=IDFM:70003&at=2026-10-28T08:00', size: 0.5, sizes: journey), 0.8);
  });

  test('back to a page locked at its highest: there, whatever it was left at', () {
    final history = SheetHistory(Routes.search);
    history.change(Routes.search, Routes.home, size: 0.5, sizes: sizesOf(Routes.home));

    final search = sizesOf(Routes.search);
    expect(history.change(Routes.home, Routes.search, size: 0.3, sizes: search), search.max);
  });
}
