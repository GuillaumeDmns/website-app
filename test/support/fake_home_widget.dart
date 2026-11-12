import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// home_widget's native side (Android) in memory: the widgets on the home screen and what the app writes for them
class FakeHomeWidget {
  FakeHomeWidget({this.widgetIds = const [], Map<String, String>? data}) : data = {...?data} {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, _handle);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  }

  static const _channel = MethodChannel('home_widget');

  /// Ids of the `NextDepartures` widgets placed
  final List<int> widgetIds;

  /// The widgets' data, as `NextDepartures.kt` reads it
  final Map<String, String> data;

  int redraws = 0;
  bool configureFinished = false;

  Future<Object?> _handle(MethodCall call) async {
    final arguments = call.arguments is Map ? (call.arguments as Map).cast<String, Object?>() : const <String, Object?>{};
    switch (call.method) {
      case 'saveWidgetData':
        final id = arguments['id']! as String;
        if (arguments['data'] case final String value) {
          data[id] = value;
        } else {
          data.remove(id);
        }
        return true;
      case 'getWidgetData':
        return data[arguments['id']];
      case 'updateWidget':
        redraws++;
        return true;
      case 'getInstalledWidgets':
        return [
          for (final id in widgetIds)
            {'widgetId': id, 'androidClassName': 'com.guillaumedamiens.app.NextDepartures', 'label': 'Prochains départs'},
        ];
      case 'finishHomeWidgetConfigure':
        configureFinished = true;
        return null;
      default:
        return null;
    }
  }
}
