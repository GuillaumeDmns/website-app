import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/map/main_map.dart';
import '../core/map/map_overlay.dart';
import '../core/map/map_panel.dart';
import '../core/offline/offline_banner.dart';
import '../features/go/go_bar.dart';
import '../features/home/nearby_departures.dart';
import '../features/map_place/map_place_sheet.dart';
import 'panel_scope.dart';
import 'routes.dart';
import 'sheet_sizes.dart';

export 'panel_scope.dart';

/// Width from which the page is shown in a side panel next to the map instead of a bottom sheet
const wideLayoutBreakpoint = 840.0;

const _sidePanelWidth = 420.0;

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
                Positioned.fill(child: MainMap(onLongPress: showMapPlaceSheet)),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    child: Center(
                      child: SizedBox(
                        width: 480,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [GoBar(), SizedBox(height: 8), OfflineBanner(), NearbyMapFilters()]),
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

class _NarrowLayout extends ConsumerStatefulWidget {
  const _NarrowLayout({required this.child});

  final Widget child;

  @override
  ConsumerState<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends ConsumerState<_NarrowLayout> with SingleTickerProviderStateMixin {
  static const _handleHeight = 22.0;

  /// Pages are laid out at least this high, and clipped below when the sheet is lower, rather than overflowing
  /// (fixed parts of a page, e.g. GO's header and dots, fit in it)
  static const _minPageHeight = 180.0;

  final _sheetController = DraggableScrollableController();

  /// The shell's own moves of the sheet, a jump each frame: the controller's animation stops as soon as a list
  /// leaves the sheet, which a page change does (the page below lets go of it, the loaded content replaces the
  /// loading one)
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..addListener(_onMoveFrame);
  double _moveFrom = 0;
  double _moveTo = 0;

  /// The sheet as the map behind sees it: where it is, where it rests
  final _panel = MapPanel();

  /// Where the sheet goes when the page changes
  late final _history = SheetHistory(ref.read(routerLocationProvider));

  /// Content heights given by the pages sized to it (pixels), see [PanelSheetScope.fitContent]
  final _fitted = <String, double>{};

  /// The size the shell animates the sheet to, null when it doesn't: the sheet's other moves are the user's
  double? _animatingTo;

  /// The user moved the sheet since the shell last placed it: a content-sized page growing doesn't move it then
  bool _userMoved = false;

  /// Snap sizes given to the sheet: the same list while they don't change (a new list has it snap again, interrupting
  /// a drag or an animation)
  List<double> _snapSizes = const [];

  Size _screen = Size.zero;
  double _topInset = 0;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetMoved);
  }

  @override
  void dispose() {
    _move.dispose();
    _sheetController.dispose();
    _panel.dispose();
    super.dispose();
  }

  void _onMoveFrame() {
    // The page's list being swapped: the next frame
    if (_sheetController.isAttached) {
      _sheetController.jumpTo(_moveFrom + (_moveTo - _moveFrom) * Curves.easeOutCubic.transform(_move.value));
    }
  }

  SheetSizes _sizesOf(String location) =>
      sheetSizes(location, screen: _screen, topInset: _topInset, fitted: _fitted[location], handle: _handleHeight);

  void _onSheetMoved() {
    final target = _animatingTo;
    if (target == null) {
      _userMoved = true;
    } else if ((_sheetController.size - target).abs() < 0.001) {
      _animatingTo = null;
    }
    _publishPanel();
  }

  /// The user takes the sheet: whatever the shell was doing with it, it is theirs now
  void _onUserDrag() {
    _move.stop();
    _animatingTo = null;
  }

  void _publishPanel() {
    final size = _sheetController.isAttached ? _sheetController.size : _sizesOf(ref.read(routerLocationProvider)).middle;
    _panel.update(live: size * _screen.height, resting: (_animatingTo ?? size) * _screen.height);
  }

  /// Where the sheet is to go once it can: it only moves with the page's list attached, which a page may build a few
  /// frames later
  double? _pendingSize;

  void _animateTo(double size) {
    _pendingSize = size;
    _moveWhenAttached(0);
  }

  void _moveWhenAttached(int frames) {
    // After the frame: the sheet is rebuilt with its new sizes first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _pendingSize;
      if (!mounted || size == null) {
        return;
      }
      if (!_sheetController.isAttached) {
        if (frames < 120) {
          WidgetsBinding.instance.scheduleFrame();
          _moveWhenAttached(frames + 1);
        }
        return;
      }
      _pendingSize = null;
      final sizes = _sizesOf(ref.read(routerLocationProvider));
      final target = size.clamp(sizes.min, sizes.max);
      _userMoved = false;
      _animatingTo = (_sheetController.size - target).abs() > 0.002 ? target : null;
      _publishPanel();
      if (_animatingTo != null) {
        _moveFrom = _sheetController.size;
        _moveTo = target;
        _move.forward(from: 0);
      }
    });
  }

  /// A content-sized page (GO) gives its content's height: its middle size. The sheet goes there for a new content
  /// ([reset]), or while the user hasn't moved it (or it rests at the previous middle): content growing as its data
  /// loads is followed, a sheet the user moved elsewhere stays there.
  void _fit(double height, {required bool reset}) {
    final location = ref.read(routerLocationProvider);
    final previous = _fitted[location];
    if (!reset && previous != null && (previous - height).abs() < 4) {
      return;
    }
    final before = _sizesOf(location).middle;
    setState(() => _fitted[location] = height);
    final resting = _sheetController.isAttached && (_sheetController.size - before).abs() < 0.01;
    if (reset || !_userMoved || resting) {
      _animateTo(_sizesOf(location).middle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    if (screen != _screen || topInset != _topInset) {
      _screen = screen;
      _topInset = topInset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _publishPanel();
        }
      });
    }
    final location = ref.watch(routerLocationProvider);
    final sizes = _sizesOf(location);
    final snapSizes = [if (sizes.middle > sizes.min && sizes.middle < sizes.max) sizes.middle];
    if (!listEquals(snapSizes, _snapSizes)) {
      _snapSizes = snapSizes;
    }

    // Another page: at its middle size, or as it was left when going back to it
    ref.listen(routerLocationProvider, (previous, next) {
      if (previous == null) {
        return;
      }
      final size = _sheetController.isAttached ? _sheetController.size : _sizesOf(previous).middle;
      final target = _history.change(previous, next, size: size, sizes: _sizesOf(next));
      if (target != null) {
        _animateTo(target);
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            // The status bar is over the map, which stays light in dark mode too: dark icons
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
              child: MainMap(panel: _panel, onLongPress: showMapPlaceSheet),
            ),
          ),
          const Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [GoBar(), SizedBox(height: 8), OfflineBanner(), NearbyMapFilters()]),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: sizes.middle,
            minChildSize: sizes.min,
            maxChildSize: sizes.max,
            snap: !sizes.locked,
            snapSizes: _snapSizes,
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
                    _SheetHandle(controller: _sheetController, sizes: [sizes.min, sizes.middle, sizes.max], onDragStart: _onUserDrag),
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
                          // A drag of the page's list, which moves the sheet (or scrolls it): the user's
                          child: NotificationListener<ScrollStartNotification>(
                            onNotification: (notification) {
                              if (notification.dragDetails != null && notification.metrics.axis == Axis.vertical) {
                                _onUserDrag();
                              }
                              return false;
                            },
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
  const _SheetHandle({required this.controller, required this.sizes, required this.onDragStart});

  final DraggableScrollableController controller;
  final List<double> sizes;
  final VoidCallback onDragStart;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onDragStart(),
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
