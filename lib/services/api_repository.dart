import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http/intercepted_client.dart';
import 'dart:convert';

import '../models/lines_response.dart';
import '../models/navitia/places.dart';
import '../models/stops_by_line_dto.dart';
import '../models/unit_idfm_dto.dart';
import 'api_interceptor.dart';

class ApiRepository {
  http.Client client = InterceptedClient.build(interceptors: [
    APIInterceptor(),
  ]);
  final _storage = const FlutterSecureStorage();

  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('https://guillaumedamiens.com/api/signin'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final token = data['jwt'];

      await _storage.write(key: 'jwt', value: token);
      return true;
    } else {
      return false;
    }
  }

  Future<LinesResponse> fetchLines() async {
    final response = await client.get(
      Uri.parse('https://guillaumedamiens.com/api/lines')
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return LinesResponse.fromJson(data);
    } else {
      throw Exception('Failed to load lines');
    }
  }

  Future<StopsByLineDTO> fetchStopsAndShape(String lineId) async {
    final response = await client.get(
      Uri.parse('https://guillaumedamiens.com/api/stops-by-line?lineId=$lineId')
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return StopsByLineDTO.fromJson(json);
    } else {
      throw Exception('Failed to load stops and shape');
    }
  }

  Future<UnitIDFMDTO> fetchNextDepartures(String stopId, String lineId) async {
    final response = await client.get(
      Uri.parse('https://guillaumedamiens.com/api/get-stop-next-passages?stopId=$stopId&lineId=$lineId'),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UnitIDFMDTO.fromJson(json);
    } else {
      throw Exception('Failed to fetch next departures');
    }
  }

  Future<Places> autocompletePlaces(String query) async {
    final response = await client.get(
      Uri.parse('https://guillaumedamiens.com/api/places?query=$query'),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return Places.fromJson(json);
    } else {
      throw Exception('Failed to autocomplete places');
    }
  }

}
