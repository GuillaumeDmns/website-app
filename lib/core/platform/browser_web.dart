// Browser features used by GO mode: notifications (Notification API) and keeping the screen on (Screen Wake Lock
// API), through JS interop; both are missing in some browsers (e.g. Safari outside an installed app), then nothing
// happens.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external bool get hidden;

  external void addEventListener(String type, JSFunction listener);
}

@JS('navigator')
external JSObject get _navigator;

extension type _WakeLock._(JSObject _) implements JSObject {
  external JSPromise<_WakeLockSentinel> request(String type);
}

extension type _WakeLockSentinel._(JSObject _) implements JSObject {
  external bool get released;

  external JSPromise<JSAny?> release();
}

@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  external factory _Notification(String title, _NotificationOptions options);

  external static String get permission;

  external static JSPromise<JSString> requestPermission();
}

extension type _NotificationOptions._(JSObject _) implements JSObject {
  external factory _NotificationOptions({String body, String tag});
}

bool get _hasNotifications => globalContext.has('Notification');

bool get pageHidden => _document.hidden;

Future<void> requestNotifications() async {
  if (!_hasNotifications || _Notification.permission != 'default') {
    return;
  }
  try {
    await _Notification.requestPermission().toDart;
  } catch (e) {
    debugPrint('Notification permission failed: $e');
  }
}

void notify(String title, String body) {
  if (!_hasNotifications || _Notification.permission != 'granted') {
    return;
  }
  // Same tag: a new alert replaces the previous one
  _Notification(title, _NotificationOptions(body: body, tag: 'go'));
}

_WakeLockSentinel? _sentinel;
bool _wanted = false;
bool _listening = false;

Future<void> keepScreenOn(bool on) async {
  _wanted = on;
  if (!_listening) {
    _listening = true;
    // The browser releases the lock when the tab is hidden: take it again when it comes back
    _document.addEventListener(
      'visibilitychange',
      (JSAny _) {
        if (_wanted && !_document.hidden) {
          _request();
        }
      }.toJS,
    );
  }
  if (on) {
    await _request();
  } else {
    final sentinel = _sentinel;
    _sentinel = null;
    if (sentinel != null && !sentinel.released) {
      await sentinel.release().toDart;
    }
  }
}

Future<void> _request() async {
  if (!_navigator.has('wakeLock') || (_sentinel != null && !_sentinel!.released)) {
    return;
  }
  try {
    _sentinel = await (_navigator['wakeLock'] as _WakeLock).request('screen').toDart;
  } catch (e) {
    debugPrint('Wake lock refused: $e');
  }
}
