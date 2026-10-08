import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../api/models.dart';

/// `08:05` in local time
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Short label of a departure as shown in lists: `À quai`, `3 min`, `14:52`, `Supprimé`.
String departureLabel(Departure departure, DateTime now) {
  final l10n = currentL10n;
  if (departure.cancelled) {
    return l10n.departureCancelled;
  }
  final seconds = departure.time.difference(now).inSeconds;
  if (departure.atStop == true || seconds <= 30) {
    return l10n.departureAtStop;
  }
  final minutes = seconds ~/ 60;
  if (minutes < 1) {
    return l10n.departureUnderOneMinute;
  }
  if (minutes < 60) {
    return l10n.minutesShort(minutes);
  }
  return formatClock(departure.time);
}

/// `250 m`, `1,2 km` (`1.2 km` in English)
String formatDistance(int meters) =>
    meters < 1000 ? '$meters m' : '${NumberFormat('0.0', currentL10n.localeName).format(meters / 1000)} km';

/// `12 min`, `1 h 05` (non-breaking spaces: never split across lines)
String formatDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) {
    return '$minutes\u00a0min';
  }
  return '${minutes ~/ 60}\u00a0h\u00a0${(minutes % 60).toString().padLeft(2, '0')}';
}

/// `2,55 €` (`€2.55` in English)
String formatFare(int cents) =>
    NumberFormat.currency(locale: currentL10n.localeName, symbol: '€', decimalDigits: 2).format(cents / 100);

/// `sam. 3 oct.` (`Sat, Oct 3`), or `aujourd'hui` / `demain`
String formatDay(DateTime time, DateTime now) {
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  return switch (day.difference(today).inDays) {
    0 => currentL10n.today,
    1 => currentL10n.tomorrow,
    _ => DateFormat.MMMEd(currentL10n.localeName).format(local),
  };
}
