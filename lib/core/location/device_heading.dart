import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_shown.dart';
import 'heading_stub.dart' if (dart.library.js_interop) 'heading_web.dart' as browser;

/// Where the device points, in degrees clockwise from north, smoothed: GO turns the map with it on foot and by bike
/// (the phone in the hand turns, the map turns). The sensor only runs while it is listened to and the app is on
/// screen (stopped here, not by the map: an app off screen draws nothing, so its widgets don't rebuild); nothing comes
/// where the device has no compass (desktop, or a browser without orientation events): the map then keeps the way's
/// direction.
final deviceHeadingProvider = StreamProvider.autoDispose<double>((ref) {
  final headings = deviceHeadings();
  if (headings == null) {
    return const Stream.empty();
  }
  final smoother = HeadingSmoother();
  final controller = StreamController<double>();
  StreamSubscription<double>? sensor;
  ref.listen(appShownProvider, (_, shown) {
    if (shown) {
      sensor ??= headings.map(smoother.add).listen(controller.add, onError: controller.addError);
    } else {
      sensor?.cancel();
      sensor = null;
    }
  }, fireImmediately: true);
  ref.onDispose(() {
    sensor?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The device's raw headings: Android's rotation vector sensor (`DeviceHeading.kt`), the browser's orientation events;
/// null without a compass here
Stream<double>? deviceHeadings() {
  if (kIsWeb) {
    return browser.deviceHeadings();
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return const EventChannel('com.guillaumedamiens.app/heading')
        .receiveBroadcastStream()
        .map((heading) => (heading as num).toDouble());
  }
  return null;
}

/// Smooths headings that come about 16 times a second: an average of directions (not of angles, which would make
/// 350° and 10° average to 180°), each new heading counting for [weight]
class HeadingSmoother {
  HeadingSmoother({this.weight = 0.3});

  final double weight;

  double? _east;
  double? _north;

  double add(double heading) {
    final radians = heading * math.pi / 180;
    final east = math.sin(radians);
    final north = math.cos(radians);
    _east = _east == null ? east : _east! + (east - _east!) * weight;
    _north = _north == null ? north : _north! + (north - _north!) * weight;
    return (math.atan2(_east!, _north!) * 180 / math.pi + 360) % 360;
  }
}

/// The turn from heading [from] to [to] the short way, in degrees (-180 to 180)
double headingDelta(double from, double to) => (to - from + 540) % 360 - 180;
