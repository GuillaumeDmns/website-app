import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:http_interceptor/models/interceptor_contract.dart';

import '../app_settings.dart';

class APIInterceptor extends InterceptorContract {
  FlutterSecureStorage storage = const FlutterSecureStorage();

  APIInterceptor();

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    final token = await storage.read(key: 'jwt');

    if (token != null) {
      final payload = _decodeJwtPayload(token);
      final exp = payload?['exp'] as int?;

      if (exp != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        if (exp <= now) {
          _redirectToLogin();
        } else {
          final remainingTime = exp - now;
          final totalTime = exp - payload?['iat'];

          if (remainingTime / totalTime <= 0.2) {
            await _renewToken();
          }
        }
      }
    }

    final newToken = await storage.read(key: 'jwt');
    if (newToken != null) {
      request.headers[HttpHeaders.authorizationHeader] = "Bearer $newToken";
    }

    request.headers[HttpHeaders.contentTypeHeader] = "application/json";
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    if (response is Response) {
      if (response.statusCode == 401) {
        _redirectToLogin();
      }
      return response;
    }
    return response;
  }

  void _redirectToLogin() async {
    await storage.delete(key: 'jwt');
    Navigator.pushReplacementNamed(AppSettings.navigatorState.currentContext!, '/login');
  }

  Future<void> _renewToken() async {
    final client = Client();
    final token = await storage.read(key: 'jwt');

    final response = await client.post(
      Uri.parse('https://guillaumedamiens.com/api/refresh'),
      headers: {
        HttpHeaders.authorizationHeader: "Bearer $token",
        HttpHeaders.contentTypeHeader: "application/json",
      },
    );

    if (response.statusCode == 200) {
      final newToken = jsonDecode(response.body)['jwt'] as String;
      await storage.write(key: 'jwt', value: newToken);
    } else {
      _redirectToLogin();
    }
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return jsonDecode(payload) as Map<String, dynamic>?;
  }
}


