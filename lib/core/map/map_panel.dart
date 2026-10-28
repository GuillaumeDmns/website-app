import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The bottom sheet over the lower part of the map (narrow layout), for the maps to keep their camera in the part left
/// above it: how high it is now ([live], each frame it moves) and where it rests or is going ([resting], the end of the
/// shell's animation, where framings are computed for), in logical pixels from the bottom of the map.
class MapPanel extends ChangeNotifier {
  MapPanel({double height = 0})
      : _live = height,
        _resting = height;

  double _live;
  double _resting;

  double get live => _live;
  double get resting => _resting;

  void update({required double live, required double resting}) {
    if ((live - _live).abs() < 0.5 && (resting - _resting).abs() < 0.5) {
      return;
    }
    _live = live;
    _resting = resting;
    notifyListeners();
  }
}

/// The most of a map's height the panel is taken to hide: higher, the sheet is the page and the map behind it isn't
/// looked at, its camera stays put
const maxPanelShare = 0.7;

/// The part of a map [height] px high that a panel [extent] px high hides, for the camera
double panelInset(double extent, double height) => math.max(0, math.min(extent, height * maxPanelShare));

/// The camera's padding framing points in the part of a map [height] px high left above a panel [extent] px high, with
/// a margin around them
EdgeInsets framePadding(double extent, double height) =>
    EdgeInsets.only(bottom: panelInset(extent, height)) + const EdgeInsets.all(48);

/// The camera's padding following the user: its center, where the user is, at 72 % of the part of a map [height] px
/// high left above a panel [extent] px high
EdgeInsets followPadding(double extent, double height) {
  final hidden = panelInset(extent, height);
  return EdgeInsets.only(top: (height - hidden) * 0.44, bottom: hidden);
}

/// How far down the screen the middle of the part of a map [height] px high left above the panel moves (logical
/// pixels, negative up) when the panel goes from [from] to [to] px high: half the change of that part. What was there
/// stays there, like Citymapper's map.
double visibleCenterShift(double from, double to, double height) =>
    (panelInset(from, height) - panelInset(to, height)) / 2;
