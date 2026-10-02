/// Route paths. Real URLs on the web: `/stops/IDFM:71264`, `/lines/C01371`.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/';
  static const search = '/search';
  static const aroundPath = '/around';

  static String stop(String stopAreaId) => '/stops/${Uri.encodeComponent(stopAreaId)}';

  static String line(String lineId) => '/lines/${Uri.encodeComponent(lineId)}';

  static String around(double lat, double lon, String name) =>
      Uri(path: aroundPath, queryParameters: {'lat': '$lat', 'lon': '$lon', 'name': name}).toString();
}
