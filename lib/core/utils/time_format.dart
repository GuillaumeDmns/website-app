import '../api/models.dart';

/// `08:05` in local time
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Short label of a departure as shown in lists: `À quai`, `3 min`, `14:52`, `Supprimé`.
String departureLabel(Departure departure, DateTime now) {
  if (departure.cancelled) {
    return 'Supprimé';
  }
  final seconds = departure.time.difference(now).inSeconds;
  if (departure.atStop == true || seconds <= 30) {
    return 'À quai';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 1) {
    return '< 1 min';
  }
  if (minutes < 60) {
    return '$minutes min';
  }
  return formatClock(departure.time);
}

/// `250 m`, `1,2 km`
String formatDistance(int meters) =>
    meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1).replaceFirst('.', ',')} km';

/// `12 min`, `1 h 05` (non-breaking spaces: never split across lines)
String formatDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) {
    return '$minutes\u00a0min';
  }
  return '${minutes ~/ 60}\u00a0h\u00a0${(minutes % 60).toString().padLeft(2, '0')}';
}

/// `2,55 €`
String formatFare(int cents) => '${(cents / 100).toStringAsFixed(2).replaceFirst('.', ',')}\u00a0€';
