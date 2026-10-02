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

  Future<SearchResult> search(String query, {int limit = 10}) =>
      _get('/api/v2/search', SearchResult.fromJson, {'q': query, 'limit': limit});

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
