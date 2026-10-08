import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../l10n/l10n.dart';
import 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart' as browser;

const _channel = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// Shares a link to [location] (a path of the app, e.g. `/stops/IDFM:71264`) on the web app: the system share sheet
/// on Android and in browsers that have one, else the link is copied.
Future<void> shareLink(BuildContext context, {required String title, required String location}) async {
  final url = Routes.webLink(location);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var shared = false;
  if (kIsWeb) {
    shared = await browser.share(title, url);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod<void>('share', {'title': title, 'text': '$title\n$url'});
      shared = true;
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }
  if (shared) {
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(SnackBar(content: Text(currentL10n.linkCopied)));
  } catch (e) {
    // Clipboard refused (some browsers): the link to select by hand
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SelectableText(url),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close))],
        ),
      );
    }
  }
}

/// Hands [text] to the user as a file: the browser's download on the web, the share sheet on Android (to save it or
/// send it), else the clipboard
Future<void> exportText(BuildContext context, {required String title, required String fileName, required String text}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (kIsWeb && browser.download(fileName, text)) {
    return;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod<void>('share', {'title': title, 'text': text});
      return;
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
  messenger?.showSnackBar(SnackBar(content: Text(currentL10n.exportCopied)));
}
