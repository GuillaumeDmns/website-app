import '../core/api/models.dart';
import '../core/config.dart';
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
  static const traffic = '/traffic';
  static const go = '/go';
  static const welcome = '/welcome';

  static String journey(JourneyRequest request) => Uri(path: journeyPath, queryParameters: request.toQuery()).toString();

  /// Detail of [option], found again from the search when the page is reloaded or opened from a link: the search,
  /// the departure time and the lines taken
  static String journeyDetailOf(JourneyRequest request, JourneyOption option) => Uri(
        path: journeyDetail,
        queryParameters: {
          ...request.toQuery(),
          'dep': option.departure.toUtc().toIso8601String(),
          'lines': option.rides.map((ride) => ride.line?.id ?? '').join(','),
        },
      ).toString();

  /// Link to [location] (a path of the app) on the web app
  static String webLink(String location) => '${AppConfig.webAppUrl}$location';

  /// Search used to choose a journey start or end; pops a `JourneyPlace`
  static String pickPlace(String title, {bool allowCurrentLocation = true}) => Uri(
        path: search,
        queryParameters: {'pick': title, if (!allowCurrentLocation) 'here': '0'},
      ).toString();

  static String stop(String stopAreaId) => '/stops/${Uri.encodeComponent(stopAreaId)}';

  /// Scheduled timetable of a stop area: [lineId] (the first line of the stop when null) on [date] (today when null)
  static String timetable(String stopAreaId, {String? lineId, DateTime? date}) => Uri(
        path: '/stops/${Uri.encodeComponent(stopAreaId)}/timetable',
        queryParameters: {
          'line': ?lineId,
          if (date != null)
            'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        },
      ).toString();

  static String line(String lineId) => '/lines/${Uri.encodeComponent(lineId)}';

  static String around(double lat, double lon, String name) =>
      Uri(path: aroundPath, queryParameters: {'lat': '$lat', 'lon': '$lon', 'name': name}).toString();
}
