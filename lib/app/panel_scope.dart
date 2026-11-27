import 'package:material_ui/material_ui.dart';

/// Gives the pages the scroll controller of the bottom sheet (narrow layout), so that scrolling their list also
/// drags the sheet. Null in the wide layout.
class PanelScrollScope extends InheritedWidget {
  const PanelScrollScope({super.key, required this.controller, required super.child});

  final ScrollController? controller;

  /// Only the page on top gets the controller: pages kept below in the panel's stack also build their lists, and
  /// the sheet's controller can drive a single list. A menu or a dialog over the page leaves it on top: losing the
  /// controller would rebuild its whole list (a scroll view without controller wraps itself in a
  /// PrimaryScrollController), and with it the state of the page.
  static ScrollController? of(BuildContext context) {
    final controller = context.dependOnInheritedWidgetOfExactType<PanelScrollScope>()?.controller;
    final route = ModalRoute.of(context);
    // Another page pushed over this one drives its secondary animation, a popup doesn't
    final onTop = route == null || route.isCurrent || route.secondaryAnimation?.status == AnimationStatus.dismissed;
    return onTop ? controller : null;
  }

  @override
  bool updateShouldNotify(PanelScrollScope oldWidget) => oldWidget.controller != controller;
}

/// Gives the pages the bottom sheet (narrow layout) to move it, e.g. down to show the map. No sheet in the wide
/// layout: its calls do nothing.
class PanelSheetScope extends InheritedWidget {
  const PanelSheetScope({
    super.key,
    required this.controller,
    required this.sizes,
    required this.onFit,
    required this.onDragStart,
    required super.child,
  });

  final DraggableScrollableController? controller;

  /// The sheet's sizes for the current page (fractions of the screen): lowest, middle, highest
  final ({double min, double middle, double max}) sizes;

  /// Middle size of the sheet for the current page (fraction of the screen)
  double get middle => sizes.middle;

  final void Function(double height, {required bool reset}) onFit;

  /// The user takes the sheet by a [SheetDragArea]
  final VoidCallback onDragStart;

  /// Pages sized to their content (GO mode): the sheet's middle size becomes [height] pixels (page content, its
  /// handle aside). The sheet goes there the first time, when [reset] (another content shown), or when it was at the
  /// previous height; a sheet the user moved elsewhere stays there.
  static void fitContent(BuildContext context, double height, {bool reset = false}) =>
      context.getInheritedWidgetOfExactType<PanelSheetScope>()?.onFit(height, reset: reset);

  @override
  bool updateShouldNotify(PanelSheetScope oldWidget) => oldWidget.controller != controller || oldWidget.sizes != sizes;
}

/// A part of the panel that isn't the page's list, such as the sheet's handle, a header fixed above the list (the
/// journey search) or GO's dots: dragged up or down, it moves the sheet, which a drag there did nothing to otherwise
/// (only the list drives the sheet). Released, the sheet goes to the closest of its sizes, or the next one in the
/// direction of a fling. Its child as it is in the wide layout and on pages locked at full height.
class SheetDragArea extends StatelessWidget {
  const SheetDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PanelSheetScope>();
    final controller = scope?.controller;
    if (scope == null || controller == null || scope.sizes.min >= scope.sizes.max) {
      return child;
    }
    final sizes = [scope.sizes.min, scope.sizes.middle, scope.sizes.max];
    final height = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      // The whole area, its gaps too; taps and sideways drags still reach what is in it
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => scope.onDragStart(),
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
      child: child,
    );
  }
}
