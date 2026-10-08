import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/l10n.dart';
import 'journey_providers.dart';
import 'journey_request.dart';
import 'widgets/journey_card.dart';
import 'widgets/journey_map.dart';
import 'widgets/journey_options_sheet.dart';

/// Option shown on the map, per search (the first one, "Suggéré", until another is chosen)
class _SelectedOption extends Notifier<int> {
  _SelectedOption(this.request);

  final JourneyRequest request;

  @override
  int build() => 0;

  void select(int index) => state = index;
}

final _selectedOptionProvider = NotifierProvider.autoDispose.family<_SelectedOption, int, JourneyRequest>(
  _SelectedOption.new,
);

/// Journey search: from / to, time, options, and the resulting options.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key, required this.request});

  final JourneyRequest request;

  void _update(BuildContext context, JourneyRequest next) => context.replace(Routes.journey(next));

  Future<void> _pickPlace(BuildContext context, {required bool from}) async {
    // Not the context after the await: this page may have been rebuilt while the search was shown
    final router = GoRouter.of(context);
    final place = await router.push<JourneyPlace>(
      Routes.pickPlace(from ? currentL10n.journeyFrom : currentL10n.journeyTo),
    );
    if (place != null) {
      router.replace(Routes.journey(from ? request.copyWith(from: place) : request.copyWith(to: place)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final plan = request.isComplete ? ref.watch(journeyPlanProvider(request)) : null;
    final user = ref.watch(userLocationProvider).value;

    LatLng? point(JourneyPlace? place) => place == null
        ? null
        : place.isCurrentLocation
        ? user
        : place.lat != null
        ? LatLng(place.lat!, place.lon!)
        : null;
    final journeys = plan?.value?.journeys ?? const <JourneyOption>[];
    final selectedIndex = ref
        .watch(_selectedOptionProvider(request))
        .clamp(0, journeys.isEmpty ? 0 : journeys.length - 1);
    final selectedJourney = journeys.isEmpty ? null : journeys[selectedIndex];

    return MapOverlayScope(
      overlay: selectedJourney != null
          ? journeyOverlay(context, selectedJourney)
          : MapOverlay(
              pins: [
                if (point(request.from) case final from?) MapPin(point: from, color: Colors.green.shade600, size: 16),
                if (point(request.to) case final to?)
                  MapPin(point: to, color: Theme.of(context).colorScheme.error, icon: Icons.place, size: 24),
              ],
              fit: [?point(request.from), ?point(request.to)],
            ),
      // Not the sheet's controller: the options scroll inside the sheet, which stays low enough to see them on the
      // map (it only moves with its handle)
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          _Header(
            request: request,
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
            onPickFrom: () => _pickPlace(context, from: true),
            onPickTo: () => _pickPlace(context, from: false),
            onSwap: () => _update(context, request.swapped()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: _Toolbar(
              time: _TimeButton(request: request, onChanged: (next) => _update(context, next)),
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Step-free journeys in one tap
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: request.wheelchair
                        ? IconButton.filled(
                            tooltip: context.l10n.wheelchairJourneysOn,
                            icon: const Icon(Icons.accessible),
                            onPressed: () => _update(context, request.copyWith(wheelchair: false)),
                          )
                        : IconButton.outlined(
                            tooltip: context.l10n.wheelchairJourneys,
                            icon: const Icon(Icons.accessible),
                            onPressed: () => _update(context, request.copyWith(wheelchair: true)),
                          ),
                  ),
                  Badge(
                    isLabelVisible: request.optionCount > 0,
                    label: Text('${request.optionCount}'),
                    child: OutlinedButton.icon(
                      style: _compact,
                      icon: const Icon(Icons.tune, size: 18),
                      label: Text(context.l10n.options),
                      onPressed: () async {
                        final next = await showJourneyOptions(context, request);
                        if (next != null && context.mounted) {
                          _update(context, next);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: plan == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.l10n.chooseFromTo, textAlign: TextAlign.center),
                  )
                : AsyncView(
                    value: plan,
                    onRetry: () => ref.invalidate(journeyPlanProvider(request)),
                    data: (plan) => _Results(
                      plan: plan,
                      now: now,
                      selectedIndex: selectedIndex,
                      onSelect: (index) => ref.read(_selectedOptionProvider(request).notifier).select(index),
                      onOpen: (journey) {
                        ref.read(selectedJourneyProvider.notifier).select(journey, request);
                        context.push(Routes.journeyDetailOf(request, journey));
                      },
                      onPage: (cursor) => _update(
                        context,
                        request.copyWith(datetime: () => cursor.datetime, arriveBy: cursor.arriveBy),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.request,
    required this.onBack,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
  });

  final JourneyRequest request;
  final VoidCallback onBack;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        Expanded(
          child: Column(
            children: [
              _PlaceField(
                label: context.l10n.journeyFrom,
                place: request.from,
                icon: Icons.trip_origin,
                color: Colors.green.shade600,
                onTap: onPickFrom,
              ),
              const SizedBox(height: 8),
              _PlaceField(
                label: context.l10n.journeyTo,
                place: request.to,
                icon: Icons.place,
                color: Theme.of(context).colorScheme.error,
                onTap: onPickTo,
              ),
            ],
          ),
        ),
        IconButton(tooltip: context.l10n.swap, icon: const Icon(Icons.swap_vert), onPressed: onSwap),
      ],
    );
  }
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.label,
    required this.place,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final JourneyPlace? place;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(place?.isCurrentLocation == true ? Icons.my_location : icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  place?.name ?? label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: place == null ? scheme.onSurfaceVariant : null, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TimeChoice { now, departAt, arriveBy }

/// Narrower than the theme's outlined buttons: the time and the options fit on a phone
final _compact = OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12));

/// Time on the left, options on the right; on two lines with a large text size
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.time, required this.actions});

  final Widget time;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
      return Wrap(runSpacing: 8, children: [time, actions]);
    }
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: time),
        ),
        actions,
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.request, required this.onChanged});

  final JourneyRequest request;
  final ValueChanged<JourneyRequest> onChanged;

  String get _label {
    final datetime = request.datetime;
    if (datetime == null) {
      return currentL10n.leaveNow;
    }
    final local = datetime.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final day = sameDay ? '' : '${DateFormat.Md(currentL10n.localeName).format(local)} ';
    final time = '$day${formatClock(datetime)}';
    return request.arriveBy ? currentL10n.arriveByTime(time) : currentL10n.leaveAtTime(time);
  }

  Future<void> _choose(BuildContext context, _TimeChoice choice) async {
    if (choice == _TimeChoice.now) {
      onChanged(request.copyWith(datetime: () => null, arriveBy: false));
      return;
    }

    final initial = (request.datetime ?? DateTime.now()).toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !context.mounted) {
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) {
      return;
    }
    final datetime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    onChanged(request.copyWith(datetime: () => datetime, arriveBy: choice == _TimeChoice.arriveBy));
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => OutlinedButton.icon(
        style: _compact,
        icon: const Icon(Icons.schedule, size: 18),
        label: Text(_label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final (choice, label) in [
          (_TimeChoice.now, context.l10n.leaveNow),
          (_TimeChoice.departAt, context.l10n.leaveAtMenu),
          (_TimeChoice.arriveBy, context.l10n.arriveByMenu),
        ])
          MenuItemButton(onPressed: () => _choose(context, choice), child: Text(label)),
      ],
    );
  }
}

/// Phone: the sheet may have been scrolled up over the map; lower it so that the option shows on the map, and keep
/// the tapped card in view
void _revealOnMap(BuildContext cardContext) {
  PanelSheetScope.showMap(cardContext);
  Future.delayed(const Duration(milliseconds: 280), () {
    if (cardContext.mounted) {
      Scrollable.ensureVisible(
        cardContext,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  });
}

class _Results extends StatelessWidget {
  const _Results({
    required this.plan,
    required this.now,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpen,
    required this.onPage,
  });

  final JourneyPlan plan;
  final DateTime now;
  final int selectedIndex;

  /// Shows the option on the map
  final ValueChanged<int> onSelect;
  final ValueChanged<JourneyOption> onOpen;
  final ValueChanged<PageCursor> onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (plan.journeys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.l10n.noJourneyFound, textAlign: TextAlign.center),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, journey) in plan.journeys.indexed) ...[
          // Category header only when it changes (Navitia returns several "rapid" options in a row)
          if (index == 0 || journeyTypeLabel(plan.journeys[index - 1].type) != journeyTypeLabel(journey.type))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                journeyTypeLabel(journey.type),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          // First tap shows the option on the map, a second one (or "Détails") opens it; hovering shows it too
          Builder(
            builder: (cardContext) => JourneyCard(
              journey: journey,
              now: now,
              selected: index == selectedIndex,
              onTap: () {
                if (index == selectedIndex) {
                  onOpen(journey);
                } else {
                  onSelect(index);
                  _revealOnMap(cardContext);
                }
              },
              onOpen: () => onOpen(journey),
              onHover: () => onSelect(index),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (plan.earlier != null)
              TextButton.icon(
                icon: const Icon(Icons.keyboard_arrow_up),
                label: Text(context.l10n.earlier),
                onPressed: () => onPage(plan.earlier!),
              ),
            const Spacer(),
            if (plan.later != null)
              TextButton.icon(
                icon: const Icon(Icons.keyboard_arrow_down),
                label: Text(context.l10n.later),
                onPressed: () => onPage(plan.later!),
              ),
          ],
        ),
      ],
    );
  }
}
