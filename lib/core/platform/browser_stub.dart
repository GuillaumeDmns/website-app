// Browser features used by GO mode, outside the web: nothing (see browser_web.dart)

Future<void> keepScreenOn(bool on) async {}

Future<bool> share(String title, String url) async => false;

bool download(String fileName, String content, {String type = 'application/json'}) => false;
