import '../features/journey/journey_request.dart';

/// Route paths. Real URLs on the web: `/stops/IDFM:71264`, `/lines/C01371`.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/';
  static const search = '/search';
  static const aroundPath = '/around';
  static const journeyPath = '/journey';
  static const journeyDetail = '/journey/detail';

  static String journey(JourneyRequest request) => Uri(path: journeyPath, queryParameters: request.toQuery()).toString();

  /// Search used to choose a journey start or end; pops a `JourneyPlace`
  static String pickPlace(String title) => Uri(path: search, queryParameters: {'pick': title}).toString();

  static String stop(String stopAreaId) => '/stops/${Uri.encodeComponent(stopAreaId)}';

  static String line(String lineId) => '/lines/${Uri.encodeComponent(lineId)}';

  static String around(double lat, double lon, String name) =>
      Uri(path: aroundPath, queryParameters: {'lat': '$lat', 'lon': '$lon', 'name': name}).toString();
}
