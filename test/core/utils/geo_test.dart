import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/utils/geo.dart';

void main() {
  const chatelet = LatLng(48.8584, 2.3470);
  const gareDeLyon = LatLng(48.8443, 2.3730);
  const nation = LatLng(48.8484, 2.3959);

  test('measures distances', () {
    expect(metersBetween(chatelet, gareDeLyon), closeTo(2440, 30));
    expect(metersBetween(chatelet, chatelet), 0);
  });

  group('MeasuredPolyline', () {
    final line = MeasuredPolyline([chatelet, gareDeLyon, nation]);

    test('knows its length and the distance to each point', () {
      expect(line.cumulative.first, 0);
      expect(line.length, closeTo(metersBetween(chatelet, gareDeLyon) + metersBetween(gareDeLyon, nation), 0.01));
    });

    test('projects a position on the line', () {
      final halfway = LatLng((chatelet.latitude + gareDeLyon.latitude) / 2, (chatelet.longitude + gareDeLyon.longitude) / 2);
      final projection = line.project(halfway)!;

      expect(projection.distance, lessThan(1));
      expect(projection.along, closeTo(line.cumulative[1] / 2, 5));
    });

    test('only looks ahead of a minimum distance', () {
      // Near Châtelet, but the progress is already past Gare de Lyon
      final projection = line.project(chatelet, minAlong: line.cumulative[1] + 10)!;

      expect(projection.along, greaterThanOrEqualTo(line.cumulative[1]));
    });

    test('finds points along the line and cuts it', () {
      expect(line.pointAt(0), chatelet);
      expect(line.pointAt(line.cumulative[1]), gareDeLyon);
      expect(line.pointAt(line.length + 100), nation);

      final (before, after) = line.split(line.cumulative[1] / 2);
      expect(before.first, chatelet);
      expect(after.last, nation);
      expect(before.last, after.first);
    });

    test('handles empty and single-point lines', () {
      expect(MeasuredPolyline(const []).project(chatelet), isNull);
      expect(MeasuredPolyline(const []).length, 0);
      expect(MeasuredPolyline(const [chatelet]).project(gareDeLyon)!.along, 0);
    });
  });
}
