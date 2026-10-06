import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../journey_preferences.dart';
import '../journey_request.dart';

/// Modes, accessibility, Vélib and walking speed, optionally kept for the next searches. Returns the updated request, null when dismissed.
Future<JourneyRequest?> showJourneyOptions(BuildContext context, JourneyRequest request) {
  return showModalBottomSheet<JourneyRequest>(
    context: context,
    // Above the whole app, not inside the panel or the bottom sheet
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _JourneyOptionsSheet(request: request),
  );
}

class _JourneyOptionsSheet extends ConsumerStatefulWidget {
  const _JourneyOptionsSheet({required this.request});

  final JourneyRequest request;

  @override
  ConsumerState<_JourneyOptionsSheet> createState() => _JourneyOptionsSheetState();
}

class _JourneyOptionsSheetState extends ConsumerState<_JourneyOptionsSheet> {
  static const _modes = [
    TransportMode.metro,
    TransportMode.rer,
    TransportMode.transilien,
    TransportMode.tram,
    TransportMode.bus,
  ];

  late Set<TransportMode> _selected = widget.request.modes.isEmpty ? _modes.toSet() : {...widget.request.modes};
  late bool _wheelchair = widget.request.wheelchair;
  late WalkingSpeed _walkingSpeed = widget.request.walkingSpeed;
  late bool _bikeShare = widget.request.bikeShare;
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      // Scrolls on small screens so that "Appliquer" stays reachable
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Options', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('Modes de transport', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in _modes)
                  FilterChip(
                    label: Text(mode.label),
                    selected: _selected.contains(mode),
                    onSelected: (selected) => setState(() {
                      final next = {..._selected};
                      selected ? next.add(mode) : next.remove(mode);
                      // At least one mode
                      if (next.isNotEmpty) {
                        _selected = next;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.accessible),
              title: const Text('Accessible en fauteuil roulant'),
              subtitle: const Text('Sans marches ni escaliers'),
              value: _wheelchair,
              onChanged: (value) => setState(() => _wheelchair = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.pedal_bike),
              title: const Text('Proposer un trajet en Vélib'),
              subtitle: const Text('Stations avec vélos et places disponibles'),
              value: _bikeShare,
              onChanged: (value) => setState(() => _bikeShare = value),
            ),
            const SizedBox(height: 8),
            Text('Vitesse de marche', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<WalkingSpeed>(
              showSelectedIcon: false,
              segments: [for (final speed in WalkingSpeed.values) ButtonSegment(value: speed, label: Text(speed.label))],
              selected: {_walkingSpeed},
              onSelectionChanged: (selection) => setState(() => _walkingSpeed = selection.first),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Garder pour mes prochains trajets'),
              subtitle: const Text('Accessibilité, Vélib et vitesse de marche'),
              value: _remember,
              onChanged: (value) => setState(() => _remember = value ?? false),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                // Every mode selected = no filter
                final modes = _selected.length == _modes.length ? <TransportMode>{} : _withLinkedModes(_selected);
                final request = widget.request
                    .copyWith(modes: modes, wheelchair: _wheelchair, walkingSpeed: _walkingSpeed, bikeShare: _bikeShare);
                if (_remember) {
                  ref.read(journeyPreferencesProvider.notifier).save(request);
                }
                Navigator.pop(context, request);
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }

  /// TER goes with Transilien, Noctilien with bus
  static Set<TransportMode> _withLinkedModes(Set<TransportMode> modes) => {
        ...modes,
        if (modes.contains(TransportMode.transilien)) TransportMode.ter,
        if (modes.contains(TransportMode.bus)) TransportMode.noctilien,
      };
}
