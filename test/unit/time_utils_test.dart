import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/utils/time_utils.dart';

void main() {
  group('TimeUtils Tests', () {
    test('getTimeFromIso8601 formats ISO string to HH:mm', () {
      final result = TimeUtils.getTimeFromIso8601('2026-08-08T14:30:00.000Z');
      expect(result, isNotEmpty);
      expect(result.contains(':'), isTrue);
    });

    test('getTimeFromIso8601 returns empty string on invalid input', () {
      expect(TimeUtils.getTimeFromIso8601(null), isEmpty);
      expect(TimeUtils.getTimeFromIso8601('invalid'), isEmpty);
    });

    test('formatTimeRelativeToNow returns French relative descriptions', () {
      final now = DateTime.now();

      final in5Min = now.add(const Duration(minutes: 5, seconds: 5)).toIso8601String();
      expect(TimeUtils.formatTimeRelativeToNow(in5Min), 'dans 5 min');

      final imm = now.add(const Duration(seconds: 10)).toIso8601String();
      expect(TimeUtils.formatTimeRelativeToNow(imm), 'À quai');

      final past = now.subtract(const Duration(minutes: 10)).toIso8601String();
      expect(TimeUtils.formatTimeRelativeToNow(past), 'Départ effectif');
    });

    test('parseNavitiaTime & formatNavitiaTime roundtrip', () {
      final navitiaStr = '20260808T143000';
      final dt = TimeUtils.parseNavitiaTime(navitiaStr);
      expect(dt.year, 2026);
      expect(dt.month, 8);
      expect(dt.day, 8);
      expect(dt.hour, 14);
      expect(dt.minute, 30);

      final formatted = TimeUtils.formatNavitiaTime(dt);
      expect(formatted, navitiaStr);
    });
  });
}
