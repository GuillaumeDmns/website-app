import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/journey/journey_providers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 8);

  test("departures are asked again every 30 s, every 2 min while they are a quarter of an hour away or more", () {
    expect(rideRefreshPeriod(null, now), const Duration(seconds: 30));
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 10)), now), const Duration(seconds: 30));
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 15)), now), const Duration(seconds: 30));
    // A connection at the end of a long ride, a journey for later
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 40)), now), const Duration(minutes: 2));
  });
}
