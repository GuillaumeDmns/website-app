import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answer of [FakeBackend]: JSON with a status, or no answer at all (network down)
class FakeResponse {
  const FakeResponse(this.data, {this.status = 200});

  /// The server can't be reached
  const FakeResponse.unreachable()
      : data = null,
        status = 0;

  /// RFC 9457 problem detail, as the backend answers its errors
  FakeResponse.problem(this.status, {String? detail, String? code})
      : data = {'status': status, 'detail': ?detail, 'code': ?code};

  final Object? data;

  /// 0: no answer
  final int status;
}

typedef FakeHandler = FakeResponse Function(RequestOptions request);

/// The backend as the app's Dio clients see it in the tests: answers per method and path, records the requests.
/// Unknown paths answer 404.
class FakeBackend implements HttpClientAdapter {
  final _routes = <String, FakeHandler>{};

  /// Every request received, in order
  final requests = <RequestOptions>[];

  /// The server can't be reached at all (network down)
  bool down = false;

  /// What `METHOD path` answers from now on ([path] without query, `*` matches one path segment)
  void on(String method, String path, FakeHandler handler) => _routes['$method $path'] = handler;

  void get(String path, Object? data, {int status = 200}) => on('GET', path, (_) => FakeResponse(data, status: status));

  void post(String path, Object? data, {int status = 200}) => on('POST', path, (_) => FakeResponse(data, status: status));

  void delete(String path, {int status = 204}) => on('DELETE', path, (_) => FakeResponse(null, status: status));

  /// Requests on [path] (and [method] when given)
  List<RequestOptions> requestsTo(String path, {String? method}) =>
      requests.where((request) => _path(request) == path && (method == null || request.method == method)).toList();

  /// Decoded like the server does (`IDFM%3A70001` → `IDFM:70001`)
  static String _path(RequestOptions request) => Uri.decodeFull(request.uri.path);

  /// A Dio client on this backend, like `dioFactoryProvider`'s
  Dio dio() => Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    // As sent: a retried request reuses its options
    requests.add(options.copyWith(headers: {...options.headers}));
    final path = _path(options);
    if (down) {
      throw DioException.connectionError(requestOptions: options, reason: 'Fake backend down');
    }
    final handler = _route(options.method, path);
    final response = handler == null ? FakeResponse.problem(404, detail: 'No fake for ${options.method} $path') : handler(options);
    if (response.status == 0) {
      throw DioException.connectionError(requestOptions: options, reason: 'Fake backend unreachable');
    }
    return ResponseBody.fromString(
      response.data == null ? '' : jsonEncode(response.data),
      response.status,
      headers: {
        Headers.contentTypeHeader: [response.status >= 400 ? 'application/problem+json' : Headers.jsonContentType],
      },
    );
  }

  FakeHandler? _route(String method, String path) {
    final exact = _routes['$method $path'];
    if (exact != null) {
      return exact;
    }
    for (final MapEntry(:key, :value) in _routes.entries) {
      final [routeMethod, routePath] = key.split(' ');
      if (routeMethod == method && _matches(routePath, path)) {
        return value;
      }
    }
    return null;
  }

  static bool _matches(String pattern, String path) {
    final expected = pattern.split('/');
    final actual = path.split('/');
    if (expected.length != actual.length) {
      return false;
    }
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != '*' && expected[i] != actual[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  void close({bool force = false}) {}
}
