import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorites_controller.dart';
import 'android_widgets.dart';

/// The stops of a query, nothing else (the widget shows a stop's departures). Without the user's position: the widget's
/// stop is the user's choice, and asking for the location here would open the system's prompt.
final _stopResultsProvider = FutureProvider.autoDispose.family<List<PlaceResult>, String>((ref, query) async {
  final result = await ref.watch(mobilityApiProvider).search(query);
  return [for (final place in result.places) if (place.type == PlaceType.stopArea) place];
});

/// The departures of the stop chosen, for its lines
final _stopDirectionsProvider = FutureProvider.autoDispose.family<StopDepartures, String>(
  (ref, stopId) => ref.watch(mobilityApiProvider).stopDepartures(stopId, limit: 5),
);

/// Whether the widget can say how long until a departure (it is drawn again every minute: Android's exact alarms)
final widgetTimeLeftProvider = FutureProvider.autoDispose<bool>((ref) => widgetBridge.canShowTimeLeft());

/// Seam for the tests: the native side of the widget's settings
abstract class WidgetBridge {
  Future<bool> canShowTimeLeft();
  Future<void> askTimeLeft();
}

class _NativeWidgetBridge implements WidgetBridge {
  static const _channel = MethodChannel('com.guillaumedamiens.app/widget');

  @override
  Future<bool> canShowTimeLeft() async {
    try {
      return await _channel.invokeMethod<bool>('canShowTimeLeft') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> askTimeLeft() async {
    try {
      await _channel.invokeMethod<void>('askTimeLeft');
    } catch (_) {}
  }
}

WidgetBridge widgetBridge = _NativeWidgetBridge();

/// Chooses what an Android home screen widget shows (design 2): the stop (favorite stops first, then a search), then,
/// if the user wants, the lines among its departures. Opened by Android when the widget is placed or
/// reconfigured ([configure]: the page ends the system's setup), and from a widget without stop.
class WidgetSetupScreen extends ConsumerStatefulWidget {
  const WidgetSetupScreen({super.key, required this.widgetId, this.configure = false});

  final int widgetId;
  final bool configure;

  @override
  ConsumerState<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends ConsumerState<WidgetSetupScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// The stop chosen (id, name); null while choosing it
  ({String id, String name})? _stop;

  /// Ids of the lines kept; null: all of them
  Set<String>? _lines;
  bool _saving = false;

  late final _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(widgetTimeLeftProvider));

  @override
  void initState() {
    super.initState();
    _lifecycle;
    // Reconfigured: from what it shows
    readWidgetChoice(widget.widgetId).then((choice) {
      if (choice != null && mounted && _stop == null) {
        setState(() {
          _stop = (id: choice.stopId, name: choice.stopName);
          _lines = choice.lines;
        });
      }
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _query = value.trim());
      }
    });
  }

  void _choose(String id, String name) => setState(() {
        _stop = (id: id, name: name);
        _lines = null;
      });

  /// [ids]: one line as the traveller sees it (the RER D and R come under two ids, from the RATP and the SNCF)
  void _toggle(Set<String> ids) => setState(() {
        final kept = {...?_lines};
        if (_lines == null) {
          _lines = ids;
        } else if (kept.containsAll(ids)) {
          kept.removeAll(ids);
          _lines = kept.isEmpty ? null : kept;
        } else {
          _lines = {...kept, ...ids};
        }
      });

  void _leave() {
    if (widget.configure) {
      // Android removes the widget placed without a stop
      SystemNavigator.pop();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  Future<void> _save(StopDepartures departures) async {
    final stop = _stop!;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await saveWidgetChoice(
      widget.widgetId,
      WidgetChoice(stopId: stop.id, stopName: stop.name, lines: _lines),
      departures,
    );
    if (!mounted) {
      return;
    }
    if (widget.configure) {
      await HomeWidget.finishHomeWidgetConfigure();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stop = _stop;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_stop != null) {
          setState(() => _stop = null);
        } else {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: stop == null ? context.l10n.close : context.l10n.back,
                      icon: Icon(stop == null ? Icons.close : Icons.arrow_back),
                      onPressed: () => stop == null ? _leave() : setState(() => _stop = null),
                    ),
                    Expanded(
                      child: Text(
                        stop?.name ?? context.l10n.widgetSetupTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: stop == null ? _stopChoice(context) : _lineChoice(context, stop.id)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stopChoice(BuildContext context) {
    final favorites = [
      for (final favorite in ref.watch(favoritesProvider).value ?? const <Favorite>[])
        if (favorite.kind == FavoriteKind.stop && favorite.stopAreaId != null) favorite,
    ];
    final searching = _query.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: favorites.isEmpty,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.widgetSetupHint,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: searching
              ? AsyncView(
                  value: ref.watch(_stopResultsProvider(_query)),
                  onRetry: () => ref.invalidate(_stopResultsProvider(_query)),
                  data: (stops) => stops.isEmpty
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.noResults))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            for (final stop in stops)
                              _StopTile(name: stop.name, lines: stop.lines, onTap: () => _choose(stop.id, stop.name)),
                          ],
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (favorites.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(context.l10n.widgetSetupFavorites, style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final favorite in favorites)
                        _StopTile(
                          name: favorite.stop?.name ?? favorite.label ?? '',
                          lines: favorite.stop?.lines ?? const [],
                          favorite: true,
                          onTap: () => _choose(favorite.stopAreaId!, favorite.stop?.name ?? favorite.label ?? ''),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.l10n.widgetSetupEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _lineChoice(BuildContext context, String stopId) {
    final value = ref.watch(_stopDirectionsProvider(stopId));
    return AsyncView(
      value: value,
      onRetry: () => ref.invalidate(_stopDirectionsProvider(stopId)),
      data: (departures) {
        // Each line once, in the stop's order, by what it is called: a train line's ids of the RATP and the SNCF together
        final lines = <String, ({LineSummary line, Set<String> ids})>{};
        for (final line in departures.lines) {
          final mode = line.line.mode.isRail ? 'rail' : line.line.mode.name;
          final key = '$mode:${line.line.name ?? line.line.id}';
          final known = lines[key];
          lines[key] = (line: known?.line ?? line.line, ids: {...?known?.ids, line.line.id});
        }
        final timeLeft = ref.watch(widgetTimeLeftProvider).value;
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (timeLeft == false)
                    AppCard(
                      onTap: () => widgetBridge.askTimeLeft(),
                      child: Row(
                        children: [
                          IconBubble(Icons.timer_outlined, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.widgetTimeLeftTitle, style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 2),
                                Text(context.l10n.widgetTimeLeftBody,
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  SectionTitle(context.l10n.widgetSetupLines, padding: const EdgeInsets.fromLTRB(0, 16, 0, 8)),
                  if (lines.isEmpty)
                    Text(context.l10n.widgetSetupNoLine, style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: Text(context.l10n.widgetSetupAll),
                          selected: _lines == null,
                          onSelected: (_) => setState(() => _lines = null),
                        ),
                        // The badge alone: a line in all its directions
                        for (final (:line, :ids) in lines.values)
                          FilterChip(
                            tooltip: line.label,
                            // Its mode beside a badge another line shares (the replacement buses of the RER D: "D")
                            label: lines.values.where((other) => other.line.name == line.name).length > 1
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    LineBadge(line, size: 24),
                                    const SizedBox(width: 6),
                                    Text(line.mode.label),
                                  ])
                                : LineBadge(line, size: 24),
                            selected: _lines?.containsAll(ids) ?? false,
                            onSelected: (_) => _toggle(ids),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _stop = null),
                    child: Text(context.l10n.widgetSetupChange),
                  ),
                  const SizedBox(width: 12),
                  // The theme's buttons take the whole width they are given
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(departures),
                      child: Text(context.l10n.widgetSetupConfirm),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.name, required this.lines, required this.onTap, this.favorite = false});

  final String name;
  final List<LineSummary> lines;
  final VoidCallback onTap;
  final bool favorite;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: IconBubble(
          favorite ? Icons.star_rounded : Icons.directions_transit,
          color: favorite ? context.colors.warning : Theme.of(context).colorScheme.primary,
        ),
        title: Text(name),
        subtitle: lines.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, runSpacing: 4, children: [for (final line in lines.take(12)) LineBadge(line, size: 18)]),
              ),
        onTap: onTap,
      );
}
