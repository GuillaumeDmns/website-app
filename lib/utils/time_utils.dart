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
}
