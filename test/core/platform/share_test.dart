import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:website_app/core/platform/share.dart';
import 'package:website_app/l10n/l10n.dart';

const _bridge = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// A page whose button exports [text] (tests run as Android)
Future<void> _pumpExport(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => exportText(context, title: 'Traces', fileName: 'go-traces.json', text: text),
            child: const Text('Export'),
          ),
        ),
      ),
    ),
  );
}

/// The native side answering [method] with [answer] (a throw when it is an exception), the calls received
List<MethodCall> _mock(WidgetTester tester, MethodChannel channel, String method, Object? Function() answer) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method != method) {
      return null;
    }
    calls.add(call);
    return answer();
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return calls;
}

void main() {
  testWidgets('an export goes to the share sheet with its file name, the native side sharing it as a file', (tester) async {
    final shared = _mock(tester, _bridge, 'share', () => null);
    await _pumpExport(tester, '[{"id": "a"}]');

    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(shared.single.arguments, {'title': 'Traces', 'text': '[{"id": "a"}]', 'fileName': 'go-traces.json'});
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an export the share sheet and the clipboard both refuse says so', (tester) async {
    // A GO trace of 1.4 MB: Android refuses it to the share sheet and to the clipboard (TransactionTooLargeException)
    _mock(tester, _bridge, 'share', () => throw PlatformException(code: 'error', message: 'TransactionTooLargeException'));
    final copied = _mock(tester, SystemChannels.platform, 'Clipboard.setData', () => throw PlatformException(code: 'error'));
    await _pumpExport(tester, 'x' * 1400000);

    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(find.text(currentL10n.exportFailed), findsOneWidget);
    expect(find.text(currentL10n.exportCopied), findsNothing);
  });

  testWidgets('an export the share sheet refuses is copied', (tester) async {
    _mock(tester, _bridge, 'share', () => throw PlatformException(code: 'error'));
    final copied = _mock(tester, SystemChannels.platform, 'Clipboard.setData', () => null);
    await _pumpExport(tester, 'trace');

    await tester.tap(find.text('Export'));
    await tester.pump();

    expect((copied.single.arguments as Map)['text'], 'trace');
    expect(find.text(currentL10n.exportCopied), findsOneWidget);
  });
}
