import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/map/main_map.dart';
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
                Positioned(top: 12, left: 12, right: 12, child: SafeArea(child: Center(child: SizedBox(width: 480, child: GoBar())))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatefulWidget {
  const _NarrowLayout({required this.child});

  final Widget child;

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<_NarrowLayout> {
  static const _minSize = 0.12;
  static const _initialSize = 0.5;

  final _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: MainMap(padding: EdgeInsets.only(bottom: height * _initialSize))),
          const Positioned(top: 8, left: 12, right: 12, child: SafeArea(child: GoBar())),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _initialSize,
            minChildSize: _minSize,
            maxChildSize: 1,
            snap: true,
            snapSizes: const [_minSize, _initialSize],
            builder: (context, scrollController) => Material(
              color: scheme.surface,
              elevation: 8,
              shadowColor: Colors.black45,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _SheetHandle(controller: _sheetController),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: PanelScrollScope(controller: scrollController, child: widget.child),
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

/// Drag handle: moves the sheet itself, since it is outside the page's list
class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.controller});

  final DraggableScrollableController controller;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (controller.isAttached) {
          controller.jumpTo((controller.size - details.delta.dy / height).clamp(_NarrowLayoutState._minSize, 1.0));
        }
      },
      onVerticalDragEnd: (details) {
        if (!controller.isAttached) {
          return;
        }
        final size = controller.size;
        final velocity = details.primaryVelocity ?? 0;
        final target = velocity < -300
            ? (size < _NarrowLayoutState._initialSize ? _NarrowLayoutState._initialSize : 1.0)
            : velocity > 300
                ? (size > _NarrowLayoutState._initialSize ? _NarrowLayoutState._initialSize : _NarrowLayoutState._minSize)
                : [_NarrowLayoutState._minSize, _NarrowLayoutState._initialSize, 1.0]
                    .reduce((a, b) => (a - size).abs() < (b - size).abs() ? a : b);
        controller.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      },
      child: SizedBox(
        height: 22,
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
