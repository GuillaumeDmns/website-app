import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  final now = DateTime(2026, 10, 10, 8, 0);

  // Loaded by the Material localizations in the app
  setUpAll(() => initializeDateFormatting());

  Departure at(Duration fromNow, {bool? atStop, String? status}) =>
      Departure(time: now.add(fromNow), realtime: true, atStop: atStop, status: status);

  group('in French', () {
    setUp(() => useLocale(const Locale('fr')));

    test('labels departures', () {
      expect(departureLabel(at(const Duration(seconds: 20)), now), 'À quai');
      expect(departureLabel(at(const Duration(minutes: 5), atStop: true), now), 'À quai');
      expect(departureLabel(at(const Duration(seconds: 45)), now), '< 1 min');
      expect(departureLabel(at(const Duration(minutes: 3, seconds: 50)), now), '3 min');
      expect(departureLabel(at(const Duration(minutes: 75)), now), '09:15');
      expect(departureLabel(at(const Duration(minutes: 3), status: 'cancelled'), now), 'Supprimé');
    });

    test('formats distances, durations and fares', () {
      expect(formatDistance(250), '250 m');
      expect(formatDistance(1234), '1,2 km');
      expect(formatDuration(12 * 60 + 20), '12 min');
      expect(formatDuration(65 * 60), '1 h 05');
      expect(formatFare(255), '2,55 €');
    });

    test('names days', () {
      expect(formatDay(DateTime(2026, 10, 10, 23), now), "aujourd'hui");
      expect(formatDay(DateTime(2026, 10, 11, 1), now), 'demain');
      expect(formatDay(DateTime(2026, 10, 13, 9), now), 'mar. 13 oct.');
    });
  });

  group('in English', () {
    setUp(() => useLocale(const Locale('en')));

    test('formats numbers the English way', () {
      expect(formatDistance(1234), '1.2 km');
      expect(formatFare(255), '€2.55');
      expect(departureLabel(at(const Duration(minutes: 3)), now), '3 min');
      expect(formatDay(DateTime(2026, 10, 13, 9), now), 'Tue, Oct 13');
    });
  });

  test('shows clock times in local time', () {
    expect(formatClock(DateTime(2026, 10, 10, 8, 5)), '08:05');
    expect(formatClock(DateTime(2026, 10, 10, 23, 59)), '23:59');
  });
}
