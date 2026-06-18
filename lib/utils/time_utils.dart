class TimeUtils {
  static String getTimeFromIso8601(String? date) {
    if (date == null) return '';
    try {
      DateTime dateTime = DateTime.parse(date).toLocal();
      return "${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}";
    } catch (e) {
      return '';
    }
  }

  static String twoDigits(int n) {
    if (n >= 10) return "$n";
    return "0$n";
  }

  static String formatTimeRelativeToNow(String? timestamp) {
    if (timestamp == null) return 'N/A';

    final departureTime = DateTime.tryParse(timestamp);
    if (departureTime == null) return 'N/A';

    final now = DateTime.now();
    final difference = departureTime.difference(now);

    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inMinutes < 60) {
      return 'in ${difference.inMinutes} min';
    } else {
      return 'in ${difference.inHours} h ${difference.inMinutes % 60} min';
    }
  }

  static String formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      if (dateTimeStr.length == 15) {
        final hour = int.parse(dateTimeStr.substring(9, 11));
        final minute = int.parse(dateTimeStr.substring(11, 13));
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      } else if (dateTimeStr.length == 6) {
        final hour = int.parse(dateTimeStr.substring(0, 2));
        final minute = int.parse(dateTimeStr.substring(2, 4));
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  static DateTime parseNavitiaTime(String timeString) {
    try {
      // Basic implementation, ensure patterns match your API
      // If simply "HHmmss":
      if (timeString.length == 6) {
        final now = DateTime.now();
        return DateTime(
          now.year, now.month, now.day,
          int.parse(timeString.substring(0, 2)),
          int.parse(timeString.substring(2, 4)),
          int.parse(timeString.substring(4, 6)),
        );
      }
      // If ISO-like "20231214T120000"
      if (timeString.length == 15) {
        return DateTime.parse(
            "${timeString.substring(0, 4)}-${timeString.substring(4, 6)}-${timeString.substring(6, 8)} ${timeString.substring(9, 11)}:${timeString.substring(11, 13)}:${timeString.substring(13, 15)}"
        );
      }
      return DateTime.parse(timeString);
    } catch (e) {
      return DateTime.now();
    }
  }

  static String formatNavitiaTime(DateTime date) {
    // Convert DateTime back to Navitia String format "YYYYMMDDTHHmmss"
    // Or just re-use the format required by your UI logic
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${date.year}${twoDigits(date.month)}${twoDigits(date.day)}T${twoDigits(date.hour)}${twoDigits(date.minute)}${twoDigits(date.second)}";
  }
}
