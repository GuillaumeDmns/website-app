// Browser features used by GO mode, outside the web: nothing (see browser_web.dart)

bool get pageHidden => false;

Future<void> requestNotifications() async {}

void notify(String title, String body) {}

Future<void> keepScreenOn(bool on) async {}

Future<bool> share(String title, String url) async => false;
