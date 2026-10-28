import 'package:flutter/material.dart';

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
  const PanelSheetScope({super.key, required this.controller, required this.middle, required this.onFit, required super.child});

  final DraggableScrollableController? controller;

  /// Middle size of the sheet for the current page (fraction of the screen)
  final double middle;

  final void Function(double height, {required bool reset}) onFit;

  /// Pages sized to their content (GO mode): the sheet's middle size becomes [height] pixels (page content, its
  /// handle aside). The sheet goes there the first time, when [reset] (another content shown), or when it was at the
  /// previous height; a sheet the user moved elsewhere stays there.
  static void fitContent(BuildContext context, double height, {bool reset = false}) =>
      context.getInheritedWidgetOfExactType<PanelSheetScope>()?.onFit(height, reset: reset);

  @override
  bool updateShouldNotify(PanelSheetScope oldWidget) => oldWidget.controller != controller || oldWidget.middle != middle;
}
