import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../l10n/l10n.dart';
import 'stop_screen.dart';

typedef TimetableKey = ({String stopAreaId, String lineId, DateTime date});

/// Scheduled timetable of a line at a stop area for a service day (kept while the app runs: it changes twice a day)
final timetableProvider = FutureProvider.autoDispose.family<Timetable, TimetableKey>((ref, key) {
  ref.keepAlive();
  return ref.watch(mobilityApiProvider).timetable(key.stopAreaId, key.lineId, date: key.date);
});

/// Scheduled timetable of a stop area, like a printed one: per line and direction, hours with their minutes. The line
/// and the day are in the URL (`/stops/{id}/timetable?line=&date=`).
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key, required this.stopAreaId, this.lineId, this.date});

  final String stopAreaId;
  final String? lineId;
  final DateTime? date;

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  int _direction = 0;

  /// Row of the current hour, scrolled to once loaded
  final _nowRow = GlobalKey();
  Object? _scrolledFor;

  static DateTime _day(DateTime time) => DateTime(time.year, time.month, time.day);

  void _open({String? lineId, DateTime? date}) {
    setState(() => _direction = 0);
    context.replace(Routes.timetable(widget.stopAreaId, lineId: lineId ?? widget.lineId, date: date ?? widget.date));
  }

  Future<void> _pickDate(DateTime current) async {
    final today = _day(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (picked != null) {
      _open(date: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stop = ref.watch(stopAreaProvider(widget.stopAreaId));
    final detail = stop.value;
    final today = _day(ref.watch(nowProvider).value ?? DateTime.now());
    final date = widget.date == null ? today : _day(widget.date!);
    final line = detail == null
        ? null
        : detail.lines.where((line) => line.id == widget.lineId).firstOrNull ?? detail.lines.firstOrNull;

    return MapOverlayScope(
      overlay: detail == null
          ? MapOverlay.empty
          : MapOverlay(
              pins: [
                MapPin(
                  point: LatLng(detail.lat, detail.lon),
                  color: theme.colorScheme.primary,
                  icon: Icons.directions_transit,
                  size: 26,
                  label: detail.name,
                ),
              ],
              fit: [LatLng(detail.lat, detail.lon)],
            ),
      child: CustomScrollView(
        controller: PanelScrollScope.of(context),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.l10n.back,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.canPop() ? context.pop() : context.go(Routes.stop(widget.stopAreaId)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.scheduledTimetable,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          detail?.name ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (detail == null)
            SliverToBoxAdapter(
              child: AsyncView(
                value: stop,
                onRetry: () => ref.invalidate(stopAreaProvider(widget.stopAreaId)),
                data: (_) => const SizedBox.shrink(),
              ),
            )
          else if (line == null)
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.noLineAtStop)),
            )
          else ...[
            // Line and day
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in detail.lines)
                      Tooltip(
                        message: '${option.mode.label} ${option.name ?? ''}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: option.id == line.id ? null : () => _open(lineId: option.id),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: option.id == line.id ? theme.colorScheme.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: LineBadge(option, size: 28),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(context.l10n.todayChip),
                      selected: date == today,
                      onSelected: (_) => _open(date: today),
                    ),
                    ChoiceChip(
                      label: Text(context.l10n.tomorrowChip),
                      selected: date == today.add(const Duration(days: 1)),
                      onSelected: (_) => _open(date: today.add(const Duration(days: 1))),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        date == today || date == today.add(const Duration(days: 1))
                            ? context.l10n.otherDate
                            : formatDay(date, today),
                      ),
                      onPressed: () => _pickDate(date),
                    ),
                  ],
                ),
              ),
            ),
            _TimetableBody(
              key: ValueKey('${line.id}|$date'),
              timetableKey: (stopAreaId: widget.stopAreaId, lineId: line.id, date: date),
              isToday: date == today,
              direction: _direction,
              onDirection: (index) => setState(() => _direction = index),
              nowRow: _nowRow,
              onLoaded: () {
                final key = '${line.id}|$date';
                if (_scrolledFor == key || date != today) {
                  return;
                }
                _scrolledFor = key;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final row = _nowRow.currentContext;
                  if (row != null) {
                    Scrollable.ensureVisible(row, duration: const Duration(milliseconds: 300), alignment: 0.2);
                  }
                });
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TimetableBody extends ConsumerWidget {
  const _TimetableBody({
    super.key,
    required this.timetableKey,
    required this.isToday,
    required this.direction,
    required this.onDirection,
    required this.nowRow,
    required this.onLoaded,
  });

  final TimetableKey timetableKey;
  final bool isToday;
  final int direction;
  final ValueChanged<int> onDirection;
  final GlobalKey nowRow;
  final VoidCallback onLoaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timetable = ref.watch(timetableProvider(timetableKey));
    final data = timetable.value;
    if (data == null) {
      return SliverToBoxAdapter(
        child: AsyncView(
          value: timetable,
          onRetry: () => ref.invalidate(timetableProvider(timetableKey)),
          data: (_) => const SizedBox.shrink(),
        ),
      );
    }
    if (data.directions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.noDepartureThatDay)),
      );
    }
    onLoaded();

    final theme = Theme.of(context);
    final shown = data.directions[direction.clamp(0, data.directions.length - 1)];
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final next = isToday ? shown.departures.where((entry) => entry.time.isAfter(now)).firstOrNull : null;

    // Destinations other than the main one get a letter, explained below the grid
    final counts = <String, int>{};
    for (final entry in shown.departures) {
      counts[entry.destination] = (counts[entry.destination] ?? 0) + 1;
    }
    final byFrequency = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final letters = {
      for (final (index, destination) in byFrequency.skip(1).indexed)
        destination: String.fromCharCode(0x61 + index % 26),
    };

    // Hours of the service day: after midnight they go on (24, 25…) to stay after the evening
    final hours = <int, List<TimetableEntry>>{};
    for (final entry in shown.departures) {
      final hour = entry.time.toLocal().difference(timetableKey.date).inHours;
      hours.putIfAbsent(hour, () => []).add(entry);
    }
    final currentHour = isToday ? now.difference(timetableKey.date).inHours : null;
    final firstShownHour = currentHour == null ? null : hours.keys.where((hour) => hour >= currentHour).firstOrNull;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      // Not lazy (a day is a few dozen rows): the current hour's row must exist to be scrolled to
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.directions.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (index, option) in data.directions.indexed)
                      ChoiceChip(
                        label: Text(context.l10n.towards(option.name), maxLines: 2, overflow: TextOverflow.ellipsis),
                        selected: option == shown,
                        onSelected: (_) => onDirection(index),
                      ),
                  ],
                ),
              ),
            Text(
              context.l10n.timetableCount(shown.departures.length, formatDay(timetableKey.date, DateTime(now.year, now.month, now.day))),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final MapEntry(key: hour, value: entries) in hours.entries)
              Container(
                key: hour == firstShownHour ? nowRow : null,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        context.l10n.timetableHour((hour % 24).toString().padLeft(2, '0')),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: currentHour != null && hour < currentHour ? theme.colorScheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          for (final entry in entries)
                            _Minute(
                              entry: entry,
                              letter: letters[entry.destination],
                              past: isToday && !entry.time.isAfter(now),
                              next: entry == next,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (byFrequency.length > 1) ...[
              const SizedBox(height: 12),
              Text(context.l10n.timetableNoLetter(byFrequency.first), style: theme.textTheme.bodySmall),
              for (final MapEntry(key: destination, value: letter) in letters.entries)
                Text(context.l10n.timetableLetter(letter, destination), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Text(
              context.l10n.timetableNotice,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minutes of a departure, with the letter of its destination; the next one is highlighted
class _Minute extends StatelessWidget {
  const _Minute({required this.entry, required this.letter, required this.past, required this.next});

  final TimetableEntry entry;
  final String? letter;
  final bool past;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = next
        ? theme.colorScheme.onPrimary
        : past
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
        : null;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: entry.time.toLocal().minute.toString().padLeft(2, '0')),
          if (letter != null)
            TextSpan(
              text: letter,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      style: TextStyle(
        color: color,
        fontWeight: next ? FontWeight.w800 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Tooltip(
      message:
          '${context.l10n.timeTowards(formatClock(entry.time), entry.destination)}${entry.mission == null ? '' : ' (${entry.mission})'}',
      child: next
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(4)),
              child: text,
            )
          : text,
    );
  }
}
