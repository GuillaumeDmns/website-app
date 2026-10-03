import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'models.dart';

/// Backend mobility endpoints (`/api/v2`).
class MobilityApi {
  MobilityApi(this._dio);

  final Dio _dio;

  Future<List<StopDepartures>> nearbyDepartures(double lat, double lon, {int radius = 500, int maxStops = 5, int limit = 3}) =>
      _getList('/api/v2/nearby/departures', StopDepartures.fromJson,
          {'lat': lat, 'lon': lon, 'radius': radius, 'maxStops': maxStops, 'limit': limit});

  Future<List<StopAreaSummary>> nearby(double lat, double lon, {int radius = 500, int limit = 20}) =>
      _getList('/api/v2/nearby', StopAreaSummary.fromJson, {'lat': lat, 'lon': lon, 'radius': radius, 'limit': limit});

  Future<StopAreaDetail> stopArea(String stopAreaId) =>
      _get('/api/v2/stops/${Uri.encodeComponent(stopAreaId)}', StopAreaDetail.fromJson);

  Future<StopDepartures> stopDepartures(String stopAreaId, {String? lineId, int limit = 3}) =>
      _get('/api/v2/stops/${Uri.encodeComponent(stopAreaId)}/departures', StopDepartures.fromJson,
          {'lineId': ?lineId, 'limit': limit});

  Future<LineDetail> line(String lineId) => _get('/api/v2/lines/${Uri.encodeComponent(lineId)}', LineDetail.fromJson);

  /// [from] / [to]: `lat,lon` or a stop area id. [modes]: allowed modes, all when empty.
  Future<JourneyPlan> journeys({
    required String from,
    required String to,
    DateTime? datetime,
    bool arriveBy = false,
    Set<TransportMode> modes = const {},
    bool wheelchair = false,
    String walkingSpeed = 'NORMAL',
  }) =>
      _get('/api/v2/journeys', JourneyPlan.fromJson, {
        'from': from,
        'to': to,
        if (datetime != null) 'datetime': datetime.toUtc().toIso8601String(),
        'arriveBy': arriveBy,
        if (modes.isNotEmpty) 'modes': modes.map((mode) => mode.apiName).join(','),
        'wheelchair': wheelchair,
        'walkingSpeed': walkingSpeed,
      });

  Future<SearchResult> search(String query, {int limit = 10}) =>
      _get('/api/v2/search', SearchResult.fromJson, {'q': query, 'limit': limit});

  Future<List<Favorite>> favorites() => _getList('/api/v2/me/favorites', Favorite.fromJson);

  /// [body]: `kind` plus `label`/`lat`/`lon`/`stopAreaId` for places, `stopAreaId` for stops, `lineId` for lines
  Future<Favorite> addFavorite(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api/v2/me/favorites', data: body);
      return Favorite.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> deleteFavorite(int id) async {
    try {
      await _dio.delete<void>('/api/v2/me/favorites/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> _get<T>(String path, T Function(Map<String, dynamic>) fromJson, [Map<String, dynamic>? query]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<T>> _getList<T>(String path, T Function(Map<String, dynamic>) fromJson, [Map<String, dynamic>? query]) async {
    try {
      final response = await _dio.get<List<dynamic>>(path, queryParameters: query);
      return response.data!.map((item) => fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
