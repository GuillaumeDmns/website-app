import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../journey_request.dart';

/// Modes, accessibility and walking speed. Returns the updated request, null when dismissed.
Future<JourneyRequest?> showJourneyOptions(BuildContext context, JourneyRequest request) {
  return showModalBottomSheet<JourneyRequest>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _JourneyOptionsSheet(request: request),
  );
}

class _JourneyOptionsSheet extends StatefulWidget {
  const _JourneyOptionsSheet({required this.request});

  final JourneyRequest request;

  @override
  State<_JourneyOptionsSheet> createState() => _JourneyOptionsSheetState();
}

class _JourneyOptionsSheetState extends State<_JourneyOptionsSheet> {
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
            const SizedBox(height: 8),
            Text('Vitesse de marche', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<WalkingSpeed>(
              showSelectedIcon: false,
              segments: [for (final speed in WalkingSpeed.values) ButtonSegment(value: speed, label: Text(speed.label))],
              selected: {_walkingSpeed},
              onSelectionChanged: (selection) => setState(() => _walkingSpeed = selection.first),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                // Every mode selected = no filter
                final modes = _selected.length == _modes.length ? <TransportMode>{} : _withLinkedModes(_selected);
                Navigator.pop(context, widget.request.copyWith(modes: modes, wheelchair: _wheelchair, walkingSpeed: _walkingSpeed));
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
