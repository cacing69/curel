import 'dart:typed_data';

import 'package:curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';
import 'package:dio/dio.dart';

abstract class CurlHttpClient {
  Future<CurlResponse> execute(Curl curl, {bool verbose = false});
  Future<CurlResponse> executeBinary(Curl curl, {bool verbose = false});
  void setUserAgent(String value);
}

class DioCurlHttpClient implements CurlHttpClient {
  final Dio _dio;
  var _userAgent = '';

  DioCurlHttpClient({Dio? dio}) : _dio = dio ?? Dio();

  @override
  void setUserAgent(String value) {
    _userAgent = value;
  }

  @override
  Future<CurlResponse> execute(Curl curl, {bool verbose = false}) =>
      _doRequest(curl, responseType: ResponseType.plain, verbose: verbose);

  @override
  Future<CurlResponse> executeBinary(Curl curl, {bool verbose = false}) =>
      _doRequest(curl, responseType: ResponseType.bytes, verbose: verbose);

  Future<CurlResponse> _doRequest(
    Curl curl, {
    required ResponseType responseType,
    bool verbose = false,
  }) async {
    final headers = <String, dynamic>{...?curl.headers};
    headers['User-Agent'] = _userAgent;

    final sw = Stopwatch()..start();
    final response = await _dio.request<dynamic>(
      curl.uri.toString(),
      data: curl.data,
      options: Options(
        method: curl.method,
        headers: headers,
        responseType: responseType,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    sw.stop();

    String? verboseLog;
    if (verbose) {
      final buf = StringBuffer();
      buf.writeln('* Request: ${curl.method} ${curl.uri}');
      buf.writeln('* Duration: ${sw.elapsedMilliseconds}ms');
      buf.writeln('');
      buf.writeln('> ${curl.method} ${curl.uri.path} HTTP/1.1');
      buf.writeln('> Host: ${curl.uri.host}');
      headers.forEach((key, value) {
        buf.writeln('> $key: $value');
      });
      buf.writeln('>');
      buf.writeln('');
      buf.writeln(
        '< HTTP/1.1 ${response.statusCode} ${response.statusMessage ?? ''}',
      );
      response.headers.map.forEach((key, values) {
        for (final v in values) {
          buf.writeln('< $key: $v');
        }
      });
      buf.writeln('<');
      verboseLog = buf.toString();
    }

    Object? body;
    if (responseType == ResponseType.bytes && response.data is! Uint8List) {
      body = Uint8List.fromList(response.data as List<int>);
    } else {
      body = response.data;
    }

    return CurlResponse(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage ?? '',
      headers: response.headers.map,
      body: body,
      verboseLog: verboseLog,
    );
  }
}
