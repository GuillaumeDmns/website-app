import 'dart:ui' show Size;

import 'routes.dart';

/// How the bottom sheet behaves on a page
class SheetProfile {
  const SheetProfile({this.peek = 110, this.middle = 0.5, this.maxMiddle = 0.8, this.full = false});

  /// Lowest height (pixels, handle included): enough for the page's header to stay readable
  final double peek;

  /// Middle size (fraction of the screen), where the sheet opens; content-sized pages give it in pixels instead
  final double middle;

  /// At most for a content-sized middle: the map keeps a part of the screen
  final double maxMiddle;

  /// Always at full height: nothing to see on the map (search, traffic), and room for the keyboard
  final bool full;

  static const _default = SheetProfile();

  static SheetProfile of(String location) {
    if (location.startsWith(Routes.search) || location.startsWith(Routes.traffic) || location.startsWith(Routes.about) ||
        location.startsWith(Routes.privacy) || location.startsWith(Routes.account)) {
      return const SheetProfile(full: true);
    }
    if (location.startsWith(Routes.go)) {
      // One compact step card, at least half of the screen for the map (drag up for the rest); lowered, the arrival
      // time and buttons stay
      return const SheetProfile(peek: 84, middle: 0.4, maxMiddle: 0.5);
    }
    if (location.startsWith(Routes.journeyPath) && !location.startsWith(Routes.journeyDetail)) {
      // Like Citymapper, the options first, the map a strip above (an option opens on its own map); lowered, the start
      // and end fields stay
      return const SheetProfile(peek: 150, middle: 0.85);
    }
    if (location.startsWith('/stops/') && !location.endsWith('/timetable')) {
      // Like Citymapper, its departures at once under the header and actions; the stop on the map above
      return const SheetProfile(middle: 0.62);
    }
    return _default;
  }
}

/// The bottom sheet's sizes on a page, fractions of the screen's height: lowest, middle (where it opens and snaps),
/// highest, and whether it stays at its highest
typedef SheetSizes = ({double min, double middle, double max, bool locked});

/// Sizes of the sheet for [location] on a [screen] whose status bar is [topInset] high (never under it); [fitted]: the
/// height of the content of a page sized to it (GO), [handle] aside
SheetSizes sheetSizes(String location, {required Size screen, required double topInset, double? fitted, double handle = 22}) {
  final profile = SheetProfile.of(location);
  final max = ((screen.height - topInset) / screen.height).clamp(0.5, 1.0);
  if (profile.full) {
    return (min: max, middle: max, max: max, locked: true);
  }
  final min = (profile.peek / screen.height).clamp(0.08, 0.4);
  final middle = fitted == null ? profile.middle : ((fitted + handle) / screen.height).clamp(min, profile.maxMiddle);
  return (min: min, middle: middle.clamp(min, max), max: max, locked: false);
}

/// Where the sheet goes when the page changes, like Citymapper: a new page opens at its middle size, going back finds
/// the page below at the height it was left at, and the same page with other parameters (a journey's options in its
/// URL, a line's direction) keeps the sheet where it is
class SheetHistory {
  SheetHistory(String location) : _pages = [(location: location, left: null)];

  /// The pages gone through, the current one last, with the size the sheet had when each was left
  final List<({String location, double? left})> _pages;

  static const _kept = 30;

  /// The size the sheet goes to for [next] (its [sizes]) coming from [previous], where it was at [size]; null: it
  /// stays where it is
  double? change(String previous, String next, {required double size, required SheetSizes sizes}) {
    if (_pages.last.location != previous) {
      _pages
        ..clear()
        ..add((location: previous, left: null));
    }
    if (Uri.parse(previous).path == Uri.parse(next).path) {
      _pages.last = (location: next, left: null);
      return size < sizes.min - 0.001 || size > sizes.max + 0.001 ? sizes.middle : null;
    }
    if (_pages.length >= 2 && _pages[_pages.length - 2].location == next) {
      _pages.removeLast();
      final left = _pages.last.left;
      return left == null ? sizes.middle : left.clamp(sizes.min, sizes.max);
    }
    _pages
      ..last = (location: previous, left: size)
      ..add((location: next, left: null));
    if (_pages.length > _kept) {
      _pages.removeAt(0);
    }
    return sizes.middle;
  }
}
