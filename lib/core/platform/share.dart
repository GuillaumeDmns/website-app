import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
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
    messenger?.showSnackBar(const SnackBar(content: Text('Lien copié')));
  } catch (e) {
    // Clipboard refused (some browsers): the link to select by hand
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SelectableText(url),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
        ),
      );
    }
  }
}
