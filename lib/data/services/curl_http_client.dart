import 'dart:io';
import 'dart:typed_data';

import 'package:curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';
import 'package:dio/dio.dart';

abstract class CurlHttpClient {
  Future<CurlResponse> execute(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
  });
  Future<CurlResponse> executeBinary(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
  });
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
  Future<CurlResponse> execute(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
  }) =>
      _doRequest(
        curl,
        responseType: ResponseType.plain,
        verbose: verbose,
        followRedirects: followRedirects,
      );

  @override
  Future<CurlResponse> executeBinary(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
  }) =>
      _doRequest(
        curl,
        responseType: ResponseType.bytes,
        verbose: verbose,
        followRedirects: followRedirects,
      );

  Future<CurlResponse> _doRequest(
    Curl curl, {
    required ResponseType responseType,
    bool verbose = false,
    bool followRedirects = false,
  }) async {
    final headers = <String, dynamic>{...?curl.headers};
    headers['User-Agent'] = _userAgent;

    final uri = curl.uri;

    // Verbose: DNS lookup
    String? resolvedIp;
    if (verbose) {
      try {
        final addresses = await InternetAddress.lookup(uri.host);
        if (addresses.isNotEmpty) {
          resolvedIp = addresses.first.address;
        }
      } catch (_) {}
    }

    final sw = Stopwatch()..start();

    String? verboseLog;
    late Response<dynamic> response;

    if (verbose) {
      final buf = StringBuffer();

      // DNS
      if (resolvedIp != null) {
        buf.writeln('* Trying $resolvedIp...');
        buf.writeln(
          '* Connected to ${uri.host} ($resolvedIp) port ${uri.port}',
        );
      }

      // TLS
      if (uri.scheme == 'https') {
        buf.writeln('* SSL connection using TLS');
      }

      var currentUrl = uri.toString();
      var currentMethod = curl.method;
      var currentData = curl.data;

      for (var i = 0; i <= (followRedirects ? 10 : 0); i++) {
        final currentUri = Uri.parse(currentUrl);

        buf.writeln('> $currentMethod ${currentUri.path} HTTP/1.1');
        buf.writeln('> Host: ${currentUri.host}');
        headers.forEach((key, value) {
          buf.writeln('> $key: $value');
        });
        buf.writeln('>');
        buf.writeln('');

        response = await _dio.request<dynamic>(
          currentUrl,
          data: currentData,
          options: Options(
            method: currentMethod,
            headers: headers,
            responseType: responseType,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 600,
          ),
        );

        buf.writeln(
          '< HTTP/1.1 ${response.statusCode} ${response.statusMessage ?? ''}',
        );
        response.headers.map.forEach((key, values) {
          for (final v in values) {
            buf.writeln('< $key: $v');
          }
        });
        buf.writeln('<');
        buf.writeln('');

        if (!followRedirects) break;

        final code = response.statusCode ?? 0;
        if (code >= 300 && code < 400) {
          final location = response.headers.value('location');
          if (location != null && i < 10) {
            final target = currentUri.resolve(location);
            buf.writeln('* Follow redirect #${i + 1}: $code → $target');
            buf.writeln('');
            currentUrl = target.toString();
            if (code == 301 || code == 302 || code == 303) {
              currentMethod = 'GET';
              currentData = null;
            }
            continue;
          }
        }
        break;
      }

      sw.stop();
      buf.writeln('* Response time: ${sw.elapsedMilliseconds}ms');
      verboseLog = buf.toString();
    } else {
      response = await _dio.request<dynamic>(
        uri.toString(),
        data: curl.data,
        options: Options(
          method: curl.method,
          headers: headers,
          responseType: responseType,
          followRedirects: followRedirects,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      sw.stop();
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
