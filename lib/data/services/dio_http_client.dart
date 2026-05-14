import 'dart:convert';
import 'dart:io';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curl_parser/curl_parser.dart' as cp;
import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;

class DioHttpClient implements CurlHttpClient {
  Dio _dio;
  var _userAgent = 'curel/1.0';

  DioHttpClient({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  void setUserAgent(String value) => _userAgent = value;

  Dio _createDio({required bool insecure}) {
    if (!insecure) return _dio;
    final client = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ))..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => client);
  }

  @override
  Future<CurlResponse> execute(
    cp.Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(curl,
      verbose: verbose, trace: trace, traceAscii: traceAscii,
      followRedirects: followRedirects,
      connectTimeout: connectTimeout, maxTime: maxTime,
      insecure: insecure);

  @override
  Future<CurlResponse> executeBinary(
    cp.Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(curl,
      verbose: verbose, trace: trace, traceAscii: traceAscii,
      followRedirects: followRedirects,
      connectTimeout: connectTimeout, maxTime: maxTime,
      insecure: insecure);

  @override
  Future<CurlResponse?> executeRaw(String curlCommand, {
    bool verbose = false,
    bool trace = false,
    bool traceAscii = false,
  }) async {
    final parsed = parseCurl(curlCommand);
    return _doRequest(parsed.curl,
        verbose: verbose || parsed.verbose,
        trace: trace || parsed.traceEnabled,
        traceAscii: traceAscii || parsed.traceAscii,
        followRedirects: parsed.followRedirects,
        connectTimeout: parsed.connectTimeout,
        maxTime: parsed.maxTime,
        insecure: parsed.insecure);
  }

  Future<CurlResponse> _doRequest(
    cp.Curl curl, {
    bool verbose = false,
    bool trace = false,
    bool traceAscii = false,
    bool followRedirects = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final verboseLog = StringBuffer();
    final traceLog = StringBuffer();

    final options = Options(
      method: curl.method,
      headers: {
        if (_userAgent.isNotEmpty) 'User-Agent': _userAgent,
        ...?curl.headers?.cast<String, String>(),
      },
      followRedirects: followRedirects,
      receiveTimeout: maxTime,
      sendTimeout: maxTime,
      connectTimeout: connectTimeout,
    );

    final dio = _createDio(insecure: insecure);

    Interceptor? _interceptor;
    if (verbose || trace) {
      _interceptor = InterceptorsWrapper(
        onRequest: (req, handler) {
          if (verbose) {
            verboseLog.writeln('> ${req.method} ${req.uri}');
            req.headers.forEach((k, v) {
              verboseLog.writeln('> $k: ${_headerVal(v)}');
            });
            verboseLog.writeln('>');
          }
          if (trace) {
            final headerBuf = StringBuffer();
            headerBuf.writeln('${req.method} ${req.uri} HTTP/1.1');
            req.headers.forEach((k, v) {
              headerBuf.writeln('$k: ${_headerVal(v)}');
            });
            headerBuf.writeln();
            final headerBytes = utf8.encode(headerBuf.toString());
            traceLog.writeln('=> Send header, ${headerBytes.length} bytes');
            traceLog.write(_toHex(headerBytes));

            if (req.data != null) {
              final reqBodyBytes = req.data is List<int>
                  ? req.data
                  : utf8.encode(req.data.toString());
              traceLog.writeln('=> Send data, ${reqBodyBytes.length} bytes');
              traceLog.write(_toHex(reqBodyBytes));
            }
          }
          handler.next(req);
        },
        onResponse: (res, handler) {
          if (verbose) {
            verboseLog.writeln('< HTTP ${res.statusCode} ${res.statusMessage}');
            res.headers.forEach((k, v) {
              verboseLog.writeln('< $k: ${_headerVal(v)}');
            });
            verboseLog.writeln('<');
          }
          if (trace) {
            final headerBuf = StringBuffer();
            headerBuf.writeln('HTTP/1.1 ${res.statusCode} ${res.statusMessage}');
            res.headers.forEach((k, v) {
              headerBuf.writeln('$k: ${_headerVal(v)}');
            });
            headerBuf.writeln();
            final headerBytes = utf8.encode(headerBuf.toString());
            traceLog.writeln('<= Recv header, ${headerBytes.length} bytes');
            traceLog.write(_toHex(headerBytes));

            final bodyData = res.data;
            if (bodyData != null) {
              final bodyBytes = bodyData is List<int>
                  ? bodyData
                  : utf8.encode(bodyData.toString());
              traceLog.writeln('<= Recv data, ${bodyBytes.length} bytes');
              traceLog.write(_toHex(bodyBytes));
            }
          }
          handler.next(res);
        },
      );
      dio.interceptors.add(_interceptor);
    }

    try {
      final response = await dio.request(
        curl.uri.toString(),
        data: curl.data,
        options: options,
      );

      stopwatch.stop();

      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headers[name] = values;
      });

      final body = response.data;
      final bodyStr = body is String
          ? body
          : body != null
              ? const JsonEncoder.withIndent('  ').convert(body)
              : null;

      return CurlResponse(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage ?? '',
        headers: headers,
        body: bodyStr,
        verboseLog: verbose ? verboseLog.toString().trim() : null,
        traceLog: trace ? traceLog.toString().trim() : null,
        executionTime: stopwatch.elapsed,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      if (verbose) {
        verboseLog.writeln('* Error: ${e.message}');
      }
      final msg = e.response != null
          ? 'HTTP ${e.response!.statusCode}: ${e.response!.statusMessage}'
          : e.message ?? e.toString();
      return CurlResponse(
        statusCode: e.response?.statusCode ?? 0,
        statusMessage: msg,
        headers: {},
        verboseLog: verbose ? verboseLog.toString().trim() : null,
        executionTime: stopwatch.elapsed,
      );
    } finally {
      if (_interceptor != null) {
        dio.interceptors.remove(_interceptor);
        _interceptor = null;
      }
    }
  }

  static String _headerVal(dynamic v) {
    if (v is List) return v.join(', ');
    return v.toString();
  }

  static String _toHex(List<int> bytes) {
    final buf = StringBuffer();
    for (var i = 0; i < bytes.length; i += 16) {
      final hex = <String>[];
      final ascii = StringBuffer();
      for (var j = 0; j < 16 && i + j < bytes.length; j++) {
        final b = bytes[i + j];
        hex.add(b.toRadixString(16).padLeft(2, '0'));
        ascii.write(b >= 32 && b <= 126 ? String.fromCharCode(b) : '.');
      }
      buf.write(i.toRadixString(16).padLeft(4, '0'));
      buf.write(': ');
      buf.write(hex.join(' ').padRight(48));
      buf.write('  ');
      buf.writeln(ascii.toString());
    }
    return buf.toString();
  }
}
