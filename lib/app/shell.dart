import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/map/main_map.dart';
import '../core/map/map_overlay.dart';
import '../core/offline/offline_banner.dart';
import '../features/go/go_bar.dart';
import 'routes.dart';

/// Width from which the page is shown in a side panel next to the map instead of a bottom sheet
const wideLayoutBreakpoint = 840.0;

const _sidePanelWidth = 420.0;

/// Gives the pages the scroll controller of the bottom sheet (narrow layout), so that scrolling their list also
/// drags the sheet. Null in the wide layout.
class PanelScrollScope extends InheritedWidget {
  const PanelScrollScope({super.key, required this.controller, required super.child});

  final ScrollController? controller;

  /// Only the page on top gets the controller: pages kept below in the panel's stack also build their lists, and
  /// the sheet's controller can drive a single list.
  static ScrollController? of(BuildContext context) {
    final controller = context.dependOnInheritedWidgetOfExactType<PanelScrollScope>()?.controller;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return isCurrent ? controller : null;
  }

  @override
  bool updateShouldNotify(PanelScrollScope oldWidget) => oldWidget.controller != controller;
}

/// Gives the pages the bottom sheet (narrow layout) to move it, e.g. down to show the map. No sheet in the wide
/// layout: its calls do nothing.
class PanelSheetScope extends InheritedWidget {
  const PanelSheetScope({super.key, required this.controller, required this.middle, required this.onFit, required super.child});

  final DraggableScrollableController? controller;

  /// Middle size of the sheet for the current page (fraction of the screen)
  final double middle;

  final void Function(double height, {required bool reset}) onFit;

  /// Lowers the sheet to its middle size when it is above, so that the map shows what the page just changed
  static void showMap(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<PanelSheetScope>();
    final controller = scope?.controller;
    if (controller != null && controller.isAttached && controller.size > scope!.middle + 0.05) {
      controller.animateTo(scope.middle, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }
  }

  /// Pages sized to their content (GO mode): the sheet's middle size becomes [height] pixels (page content, its
  /// handle aside). The sheet goes there the first time, when [reset] (another content shown), or when it was at the
  /// previous height; a sheet the user moved elsewhere stays there.
  static void fitContent(BuildContext context, double height, {bool reset = false}) =>
      context.getInheritedWidgetOfExactType<PanelSheetScope>()?.onFit(height, reset: reset);

  @override
  bool updateShouldNotify(PanelSheetScope oldWidget) => oldWidget.controller != controller || oldWidget.middle != middle;
}

/// Map behind, current page in a side panel (wide) or a draggable bottom sheet (narrow), like Citymapper.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.slash): _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) => context.push(Routes.search)),
          _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) {
            if (context.canPop()) {
              context.pop();
            }
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= wideLayoutBreakpoint
                ? _WideLayout(child: child)
                : _NarrowLayout(child: child),
          ),
        ),
      ),
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _sidePanelWidth,
            child: Material(
              color: scheme.surface,
              child: SafeArea(child: PanelScrollScope(controller: null, child: child)),
            ),
          ),
          VerticalDivider(width: 1, color: scheme.outline),
          const Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: MainMap()),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    child: Center(
                      child: SizedBox(
                        width: 480,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [GoBar(), SizedBox(height: 8), OfflineBanner()]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How the bottom sheet behaves on a page
class _SheetProfile {
  const _SheetProfile({this.peek = 110, this.middle = 0.5, this.full = false});

  /// Lowest height (pixels, handle included): enough for the page's header to stay readable
  final double peek;

  /// Middle size (fraction of the screen), where the sheet opens; content-sized pages give it in pixels instead
  final double middle;

  /// At most for a content-sized middle: the map keeps a part of the screen
  final double maxMiddle = 0.8;

  /// Always at full height: nothing to see on the map (search, traffic), and room for the keyboard
  final bool full;

  static const _default = _SheetProfile();

  static _SheetProfile of(String location) {
    if (location.startsWith(Routes.search) || location.startsWith(Routes.traffic) || location.startsWith(Routes.about)) {
      return const _SheetProfile(full: true);
    }
    if (location.startsWith(Routes.go)) {
      // One step card, most of the screen for the map; lowered, the arrival time and buttons stay
      return const _SheetProfile(peek: 84, middle: 0.45);
    }
    if (location.startsWith(Routes.journeyPath) && !location.startsWith(Routes.journeyDetail)) {
      // Start and end fields stay
      return const _SheetProfile(peek: 150);
    }
    return _default;
  }
}

class _NarrowLayout extends ConsumerStatefulWidget {
  const _NarrowLayout({required this.child});

  final Widget child;

  @override
  ConsumerState<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends ConsumerState<_NarrowLayout> {
  static const _handleHeight = 22.0;

  /// Pages are laid out at least this high, and clipped below when the sheet is lower, rather than overflowing
  /// (fixed parts of a page, e.g. GO's header and dots, fit in it)
  static const _minPageHeight = 180.0;

  final _sheetController = DraggableScrollableController();

  /// Content height given by the page shown (pixels), see [PanelSheetScope.fitContent]
  double? _fitted;
  String? _fittedFor;

  /// Last move of the sheet to a content height: content growing right after (data loaded) is followed too
  DateTime? _fittedAt;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  /// Sizes of the sheet (fractions of the screen) for [location]
  ({double min, double middle, double max, bool locked}) _sizes(String location, Size screen, double topInset) {
    final profile = _SheetProfile.of(location);
    // Never under the status bar
    final max = ((screen.height - topInset) / screen.height).clamp(0.5, 1.0);
    if (profile.full) {
      return (min: max, middle: max, max: max, locked: true);
    }
    final min = (profile.peek / screen.height).clamp(0.08, 0.4);
    final fitted = _fittedFor == location ? _fitted : null;
    final middle = fitted == null
        ? profile.middle
        : ((fitted + _handleHeight) / screen.height).clamp(min, profile.maxMiddle);
    return (min: min, middle: middle.clamp(min, max), max: max, locked: false);
  }

  void _animateTo(double size) {
    // After the frame: the sheet is rebuilt with its new sizes first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached && (_sheetController.size - size).abs() > 0.005) {
        _sheetController.animateTo(size, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      }
    });
  }

  void _fit(double height, {required bool reset}) {
    final location = ref.read(routerLocationProvider);
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final previous = _fittedFor == location ? _fitted : null;
    if (previous != null && (previous - height).abs() < 4 && !reset) {
      return;
    }
    final before = _sizes(location, screen, topInset).middle;
    final atPrevious = _sheetController.isAttached && (_sheetController.size - before).abs() < 0.03;
    final justFitted = _fittedAt != null && DateTime.now().difference(_fittedAt!) < const Duration(seconds: 2);
    setState(() {
      _fitted = height;
      _fittedFor = location;
    });
    if (previous == null || reset || atPrevious || justFitted) {
      _fittedAt = DateTime.now();
      _animateTo(_sizes(location, screen, topInset).middle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final location = ref.watch(routerLocationProvider);
    final sizes = _sizes(location, screen, topInset);

    // Another page: to its middle size when it differs (or when the sheet is out of its bounds)
    ref.listen(routerLocationProvider, (previous, next) {
      if (previous == null) {
        return;
      }
      final from = _sizes(previous, screen, topInset);
      final to = _sizes(next, screen, topInset);
      final size = _sheetController.isAttached ? _sheetController.size : from.middle;
      if (to.middle != from.middle || to.locked != from.locked || size < to.min || size > to.max) {
        _animateTo(to.middle);
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: MainMap(padding: EdgeInsets.only(bottom: screen.height * sizes.middle))),
          const Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [GoBar(), SizedBox(height: 8), OfflineBanner()]),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: sizes.middle,
            minChildSize: sizes.min,
            maxChildSize: sizes.max,
            snap: !sizes.locked,
            snapSizes: [if (sizes.middle > sizes.min && sizes.middle < sizes.max) sizes.middle],
            builder: (context, scrollController) => Material(
              color: scheme.surface,
              elevation: 8,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.vertical(top: Radius.circular(sizes.locked ? 0 : 20)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (sizes.locked)
                    const SizedBox(height: 8)
                  else
                    _SheetHandle(controller: _sheetController, sizes: [sizes.min, sizes.middle, sizes.max]),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: PanelSheetScope(
                        controller: _sheetController,
                        middle: sizes.middle,
                        onFit: _fit,
                        child: PanelScrollScope(
                          controller: scrollController,
                          child: LayoutBuilder(
                            builder: (context, constraints) => constraints.maxHeight >= _minPageHeight
                                ? widget.child
                                // Lowered sheet: the top of the page shows, the rest is cut
                                : ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.topCenter,
                                      minHeight: _minPageHeight,
                                      maxHeight: _minPageHeight,
                                      child: widget.child,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag handle: moves the sheet itself, since it is outside the page's list; released, it goes to the closest of
/// [sizes] (or the next one in the direction of a fling)
class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.controller, required this.sizes});

  final DraggableScrollableController controller;
  final List<double> sizes;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (controller.isAttached) {
          controller.jumpTo((controller.size - details.delta.dy / height).clamp(sizes.first, sizes.last));
        }
      },
      onVerticalDragEnd: (details) {
        if (!controller.isAttached) {
          return;
        }
        final size = controller.size;
        final velocity = details.primaryVelocity ?? 0;
        final target = velocity < -300
            ? sizes.firstWhere((s) => s > size + 0.01, orElse: () => sizes.last)
            : velocity > 300
                ? sizes.lastWhere((s) => s < size - 0.01, orElse: () => sizes.first)
                : sizes.reduce((a, b) => (a - size).abs() < (b - size).abs() ? a : b);
        controller.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      },
      child: SizedBox(
        height: _NarrowLayoutState._handleHeight,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
