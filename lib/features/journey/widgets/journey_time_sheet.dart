import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../journey_request.dart';

enum _When { now, leaveAt, arriveBy }

/// "Quand partir ?" (design 2e2): now, leave at or arrive by, then a day and a time in one sheet, applied with one
/// button. Returns the search moved to that time, or null when dismissed.
Future<JourneyRequest?> showJourneyTimeSheet(BuildContext context, JourneyRequest request) => showModalBottomSheet<JourneyRequest>(
      context: context,
      // Above the whole app, not inside the panel or the bottom sheet
      useRootNavigator: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      backgroundColor: context.colors.card,
      builder: (context) => _TimeSheet(request: request),
    );

class _TimeSheet extends StatefulWidget {
  const _TimeSheet({required this.request});

  final JourneyRequest request;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  static const _minuteStep = 5;
  static const _itemExtent = 40.0;

  late _When _when = widget.request.datetime == null
      ? _When.now
      : widget.request.arriveBy
          ? _When.arriveBy
          : _When.leaveAt;

  /// The day chosen (local, at midnight) and the time on it
  late DateTime _day;
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hours;
  late final FixedExtentScrollController _minutes;

  @override
  void initState() {
    super.initState();
    // A time already chosen, else now rounded up to the next 5 minutes
    var initial = (widget.request.datetime ?? DateTime.now()).toLocal();
    if (widget.request.datetime == null) {
      initial = initial.add(Duration(minutes: (_minuteStep - initial.minute % _minuteStep) % _minuteStep));
    }
    _day = DateTime(initial.year, initial.month, initial.day);
    _hour = initial.hour;
    _minute = initial.minute - initial.minute % _minuteStep;
    _hours = FixedExtentScrollController(initialItem: _hour);
    _minutes = FixedExtentScrollController(initialItem: _minute ~/ _minuteStep);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _chosen => DateTime(_day.year, _day.month, _day.day, _hour, _minute);

  String _dayWords(BuildContext context) {
    final days = _day.difference(_today).inDays;
    return switch (days) {
      0 => context.l10n.today,
      1 => context.l10n.tomorrow,
      _ => DateFormat.MMMEd(context.l10n.localeName).format(_day),
    };
  }

  Future<void> _otherDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _today.subtract(const Duration(days: 1)),
      lastDate: _today.add(const Duration(days: 30)),
    );
    if (date != null && mounted) {
      setState(() => _day = date);
    }
  }

  void _apply() {
    HapticFeedback.lightImpact();
    Navigator.pop(
      context,
      _when == _When.now
          ? widget.request.copyWith(datetime: () => null, arriveBy: false)
          : widget.request.copyWith(datetime: () => _chosen, arriveBy: _when == _When.arriveBy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final timed = _when != _When.now;
    final days = _day.difference(_today).inDays;

    Widget dayChip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Material(
          color: selected ? theme.colorScheme.primary.withValues(alpha: theme.brightness == Brightness.light ? 0.14 : 0.24) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: selected ? BorderSide.none : BorderSide(color: theme.colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    Widget wheel({required FixedExtentScrollController controller, required int count, required String Function(int) label,
        required ValueChanged<int> onChanged, required String semantics}) {
      final style = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()]);
      return SizedBox(
        width: 64,
        child: Semantics(
          label: semantics,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _itemExtent,
            diameterRatio: 1.6,
            overAndUnderCenterOpacity: 0.35,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              HapticFeedback.selectionClick();
              onChanged(index);
            },
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [for (var i = 0; i < count; i++) Center(child: Text(label(i), style: style))],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(context.l10n.timeSheetTitle, style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
            ),
            // Now, leave at, arrive by
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: colors.subtle, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  for (final (choice, label) in [
                    (_When.now, context.l10n.timeNow),
                    (_When.leaveAt, context.l10n.timeLeaveAt),
                    (_When.arriveBy, context.l10n.timeArriveBy),
                  ])
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: _when == choice,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _when = choice),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(14) + 24),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _when == choice ? colors.card : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _when == choice ? const [BoxShadow(color: Color(0x24000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                            ),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 14,
                                fontWeight: _when == choice ? FontWeight.w600 : FontWeight.w500,
                                color: _when == choice ? null : colors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (timed) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  dayChip(context.l10n.timeTodayCapital, days == 0, () => setState(() => _day = _today)),
                  dayChip(context.l10n.timeTomorrowCapital, days == 1, () => setState(() => _day = _today.add(const Duration(days: 1)))),
                  dayChip(
                    days > 1 || days < 0 ? DateFormat.MMMEd(context.l10n.localeName).format(_day) : context.l10n.otherDate,
                    days > 1 || days < 0,
                    _otherDate,
                    icon: Icons.calendar_today,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: _itemExtent * 5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The band of the time chosen
                    Container(
                      height: _itemExtent,
                      decoration: BoxDecoration(color: colors.subtle, borderRadius: BorderRadius.circular(12)),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        wheel(
                          controller: _hours,
                          count: 24,
                          label: (i) => i.toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _hour = i),
                          semantics: context.l10n.timeHours,
                        ),
                        Text(':', style: theme.textTheme.headlineSmall),
                        wheel(
                          controller: _minutes,
                          count: 60 ~/ _minuteStep,
                          label: (i) => (i * _minuteStep).toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _minute = i * _minuteStep),
                          semantics: context.l10n.timeMinutes,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (_when == _When.arriveBy ? context.l10n.timeSummaryArrive : context.l10n.timeSummaryLeave)(
                    formatClock(_chosen.toUtc()), _dayWords(context)),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: colors.muted),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _apply, child: Text(context.l10n.apply)),
          ],
        ),
      ),
    );
  }
}
