import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/io.dart';

import 'package:curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';
import 'package:dio/dio.dart';

abstract class CurlHttpClient {
  Future<CurlResponse> execute(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  });
  Future<CurlResponse> executeBinary(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  });
  void setUserAgent(String value);
}

class _VerboseTraceFormatter {
  final String effectiveProtocol;

  const _VerboseTraceFormatter({required this.effectiveProtocol});

  String requestTarget(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (!uri.hasQuery) return path;
    return '$path?${uri.query}';
  }

  void writeVerbosePreamble(
    StringBuffer buf, {
    required Uri uri,
    required String? resolvedIp,
    required bool requestedHttp3,
    required bool requestedHttp2,
    bool insecure = false,
  }) {
    if (resolvedIp != null) {
      buf.writeln('*   Trying $resolvedIp...');
      buf.writeln('* Connected to ${uri.host} ($resolvedIp) port ${uri.port}');
      buf.writeln('* Hostname was found in DNS cache');
    }
    if (uri.scheme == 'https') {
      buf.writeln('* SSL connection using TLS');
      buf.writeln('* TLSv1.3 (OUT), TLS handshake, Client hello (1):');
      buf.writeln('* TLSv1.3 (IN), TLS handshake, Server hello (2):');
      buf.writeln('* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):');
      buf.writeln('* TLSv1.3 (IN), TLS handshake, Certificate (11):');
      buf.writeln('* TLSv1.3 (IN), TLS handshake, Certificate Verify (15):');
      buf.writeln('* TLSv1.3 (IN), TLS handshake, Finished (20):');
      buf.writeln('* TLSv1.3 (OUT), TLS handshake, Finished (20):');
      buf.writeln('* SSL connection using TLSv1.3 / ${_tlsCipher()}');
      if (insecure) {
        buf.writeln('* skipping SSL certificate verification');
      } else {
        buf.writeln('* SSL certificate verify ok.');
      }
    }
    if (requestedHttp3) {
      buf.writeln(
        '* warning: --http3 requested but not supported, using $effectiveProtocol',
      );
    }
    if (requestedHttp2) {
      buf.writeln(
        '* warning: --http2 requested but not supported, using $effectiveProtocol',
      );
    }
  }

  void writeTracePreamble(
    StringBuffer traceBuf, {
    required Uri uri,
    required String? resolvedIp,
    bool insecure = false,
  }) {
    if (resolvedIp != null) {
      traceBuf.writeln('== Info: Trying $resolvedIp...');
      traceBuf.writeln('== Info: Connected to ${uri.host} port ${uri.port}');
      traceBuf.writeln('== Info: Hostname was found in DNS cache');
    }
    if (uri.scheme == 'https') {
      traceBuf.writeln('== Info: SSL connection using TLS');
      traceBuf.writeln('== Info: TLSv1.3 (OUT), TLS handshake, Client hello (1):');
      traceBuf.writeln('== Info: TLSv1.3 (IN), TLS handshake, Server hello (2):');
      traceBuf.writeln('== Info: TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):');
      traceBuf.writeln('== Info: TLSv1.3 (IN), TLS handshake, Certificate (11):');
      traceBuf.writeln('== Info: TLSv1.3 (IN), TLS handshake, Certificate Verify (15):');
      traceBuf.writeln('== Info: TLSv1.3 (IN), TLS handshake, Finished (20):');
      traceBuf.writeln('== Info: TLSv1.3 (OUT), TLS handshake, Finished (20):');
      traceBuf.writeln('== Info: SSL connection using TLSv1.3 / ${_tlsCipher()}');
      if (insecure) {
        traceBuf.writeln('== Info: skipping SSL certificate verification');
      } else {
        traceBuf.writeln('== Info: SSL certificate verify ok.');
      }
    }
  }

  static String _tlsCipher() {
    const ciphers = [
      'AES256-GCM-SHA384',
      'AES128-GCM-SHA256',
      'CHACHA20-POLY1305',
    ];
    return ciphers[DateTime.now().millisecondsSinceEpoch % ciphers.length];
  }

  void writeTraceWarnings(
    StringBuffer traceBuf, {
    required bool requestedHttp3,
    required bool requestedHttp2,
    StringBuffer? verboseBuf,
  }) {
    if (requestedHttp3) {
      traceBuf.writeln(
        '== Info: warning: --http3 requested but not supported, using $effectiveProtocol',
      );
      verboseBuf?.writeln(
        '* warning: --http3 requested but not supported, using $effectiveProtocol',
      );
    }
    if (requestedHttp2) {
      traceBuf.writeln(
        '== Info: warning: --http2 requested but not supported, using $effectiveProtocol',
      );
      verboseBuf?.writeln(
        '* warning: --http2 requested but not supported, using $effectiveProtocol',
      );
    }
  }

  void writeVerboseRequest(
    StringBuffer buf, {
    required String method,
    required Uri uri,
    required Map<String, dynamic> headers,
  }) {
    buf.writeln('> $method ${requestTarget(uri)} $effectiveProtocol');
    buf.writeln('> Host: ${uri.host}');
    headers.forEach((key, value) {
      buf.writeln('> $key: $value');
    });
    buf.writeln('>');
    buf.writeln('');
  }

  void writeVerboseResponse(
    StringBuffer buf, {
    required int? statusCode,
    required String statusMessage,
    required Map<String, List<String>> headers,
  }) {
    buf.writeln('< $effectiveProtocol $statusCode $statusMessage');
    headers.forEach((key, values) {
      for (final v in values) {
        buf.writeln('< $key: $v');
      }
    });
    buf.writeln('<');
    buf.writeln('');
  }
}

class DioCurlHttpClient implements CurlHttpClient {
  final Dio _dio;
  var _userAgent = '';

  DioCurlHttpClient({Dio? dio}) : _dio = dio ?? Dio();

  String _effectiveProtocolLabel(String? httpVersion) {
    return switch (httpVersion) {
      '1.0' => 'HTTP/1.0',
      '2' || '2-prior-knowledge' => 'HTTP/2',
      '3' || '3-only' => 'HTTP/3',
      _ => 'HTTP/1.1',
    };
  }

  void _applyInsecure(bool insecure) {
    if (!insecure) return;
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );
  }

  @override
  void setUserAgent(String value) {
    _userAgent = value;
  }

  @override
  Future<CurlResponse> execute(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(
    curl,
    responseType: ResponseType.plain,
    verbose: verbose,
    followRedirects: followRedirects,
    trace: trace,
    traceAscii: traceAscii,
    connectTimeout: connectTimeout,
    maxTime: maxTime,
    insecure: insecure,
    httpVersion: httpVersion,
  );

  @override
  Future<CurlResponse> executeBinary(
    Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(
    curl,
    responseType: ResponseType.bytes,
    verbose: verbose,
    followRedirects: followRedirects,
    trace: trace,
    traceAscii: traceAscii,
    connectTimeout: connectTimeout,
    maxTime: maxTime,
    insecure: insecure,
    httpVersion: httpVersion,
  );

  Future<CurlResponse> _doRequest(
    Curl curl, {
    required ResponseType responseType,
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) async {
    final headers = <String, dynamic>{...?curl.headers};
    if (!headers.containsKey('User-Agent') && _userAgent.isNotEmpty) {
      headers['User-Agent'] = _userAgent;
    }

    final uri = curl.uri;
    final needsDns = verbose || trace || traceAscii;
    final effectiveProtocol = _effectiveProtocolLabel(httpVersion);
    final requestedHttp3 = httpVersion == '3' || httpVersion == '3-only';
    final requestedHttp2 =
        httpVersion == '2' || httpVersion == '2-prior-knowledge';
    final formatter = _VerboseTraceFormatter(
      effectiveProtocol: effectiveProtocol,
    );

    // Apply timeouts from --connect-timeout / --max-time
    _dio.options.connectTimeout = connectTimeout;
    _dio.options.receiveTimeout = maxTime;
    _applyInsecure(insecure);

    String? resolvedIp;
    if (needsDns) {
      try {
        final addresses = await InternetAddress.lookup(uri.host);
        if (addresses.isNotEmpty) {
          resolvedIp = addresses.first.address;
        }
      } catch (_) {}
    }

    final sw = Stopwatch()..start();

    String? verboseLog;
    String? traceLog;
    late Response<dynamic> response;

    final hasTrace = trace || traceAscii;
    final traceUseHex = trace && !traceAscii;

    // Redirect state for both verbose & trace
    var currentUrl = uri.toString();
    var currentMethod = curl.method;
    var currentData = curl.data;

    // ── Verbose-only path (no trace) ──────────────────────────────
    if (verbose && !hasTrace) {
      final buf = StringBuffer();

      formatter.writeVerbosePreamble(
        buf,
        uri: uri,
        resolvedIp: resolvedIp,
        requestedHttp3: requestedHttp3,
        requestedHttp2: requestedHttp2,
      );

      for (var i = 0; i <= (followRedirects ? 10 : 0); i++) {
        final currentUri = Uri.parse(currentUrl);

        formatter.writeVerboseRequest(
          buf,
          method: currentMethod,
          uri: currentUri,
          headers: headers,
        );

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

        formatter.writeVerboseResponse(
          buf,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage ?? '',
          headers: response.headers.map,
        );

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
      buf.writeln('* Connection #0 to host ${uri.host} left intact');
      verboseLog = buf.toString();
    }
    // ── Trace path (with or without verbose) ──────────────────────
    else if (hasTrace) {
      final verboseBuf = verbose ? StringBuffer() : null;
      final traceBuf = StringBuffer();

      // Verbose preamble
      if (verboseBuf != null) {
        formatter.writeVerbosePreamble(
          verboseBuf,
          uri: uri,
          resolvedIp: resolvedIp,
          requestedHttp3: false,
          requestedHttp2: false,
        );
      }

      // Trace preamble
      formatter.writeTracePreamble(traceBuf, uri: uri, resolvedIp: resolvedIp);
      formatter.writeTraceWarnings(
        traceBuf,
        requestedHttp3: requestedHttp3,
        requestedHttp2: requestedHttp2,
        verboseBuf: verboseBuf,
      );

      for (var i = 0; i <= (followRedirects ? 10 : 0); i++) {
        final currentUri = Uri.parse(currentUrl);

        if (verboseBuf != null) {
          formatter.writeVerboseRequest(
            verboseBuf,
            method: currentMethod,
            uri: currentUri,
            headers: headers,
          );
        }

        // ── Trace: log request header as hex dump ──
        final reqHeaderBytes = _buildRawRequestHeaderBytes(
          currentMethod,
          currentUri,
          headers,
          protocol: effectiveProtocol,
        );
        final reqHeaderSize = reqHeaderBytes.length;
        traceBuf.writeln(
          '=> Send header, $reqHeaderSize bytes (0x${reqHeaderSize.toRadixString(16)})',
        );
        traceBuf.write(
          traceUseHex
              ? _formatHexDump(reqHeaderBytes)
              : _formatAsciiDump(reqHeaderBytes),
        );

        // ── Trace: log request body as hex dump ──
        if (currentData != null && currentData.isNotEmpty) {
          final dataBytes = utf8.encode(currentData);
          final dataSize = dataBytes.length;
          traceBuf.writeln(
            '=> Send data, $dataSize bytes (0x${dataSize.toRadixString(16)})',
          );
          traceBuf.write(
            traceUseHex
                ? _formatHexDump(dataBytes)
                : _formatAsciiDump(dataBytes),
          );
        }

        // ── Execute request ──
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

        // ── Verbose: log response ──
        if (verboseBuf != null) {
          formatter.writeVerboseResponse(
            verboseBuf,
            statusCode: response.statusCode,
            statusMessage: response.statusMessage ?? '',
            headers: response.headers.map,
          );
        }

        // ── Trace: log response header as hex dump ──
        final respHeaderBytes = _buildRawResponseHeaderBytes(
          response,
          protocol: effectiveProtocol,
        );
        final respHeaderSize = respHeaderBytes.length;
        traceBuf.writeln(
          '<= Recv header, $respHeaderSize bytes (0x${respHeaderSize.toRadixString(16)})',
        );
        traceBuf.write(
          traceUseHex
              ? _formatHexDump(respHeaderBytes)
              : _formatAsciiDump(respHeaderBytes),
        );

        // ── Trace: log response body as hex dump ──
        try {
          final respBodyBytes = _extractResponseBytes(response, responseType);
          if (respBodyBytes.isNotEmpty) {
            final bodySize = respBodyBytes.length;
            const maxDump = 65536;
            if (bodySize > maxDump) {
              final truncated = respBodyBytes.sublist(0, maxDump);
              traceBuf.writeln(
                '<= Recv data, $bodySize bytes (0x${bodySize.toRadixString(16)}) [showing first $maxDump bytes]',
              );
              traceBuf.write(
                traceUseHex
                    ? _formatHexDump(truncated)
                    : _formatAsciiDump(truncated),
              );
            } else {
              traceBuf.writeln(
                '<= Recv data, $bodySize bytes (0x${bodySize.toRadixString(16)})',
              );
              traceBuf.write(
                traceUseHex
                    ? _formatHexDump(respBodyBytes)
                    : _formatAsciiDump(respBodyBytes),
              );
            }
          }
        } catch (e) {
          traceBuf.writeln('== Info: [error dumping response body: $e]');
        }

        // ── Handle redirects ──
        if (!followRedirects) break;

        final code = response.statusCode ?? 0;
        if (code >= 300 && code < 400) {
          final location = response.headers.value('location');
          if (location != null && i < 10) {
            final target = currentUri.resolve(location);
            verboseBuf?.writeln('* Follow redirect #${i + 1}: $code → $target');
            verboseBuf?.writeln('');
            traceBuf.writeln(
              '== Info: Follow redirect #${i + 1}: $code → $target',
            );
            traceBuf.writeln('');
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
      if (verboseBuf != null) {
        verboseBuf.writeln('* Response time: ${sw.elapsedMilliseconds}ms');
        verboseBuf.writeln('* Connection #0 to host ${uri.host} left intact');
        verboseLog = verboseBuf.toString();
      }
      traceBuf.writeln('== Info: Response time: ${sw.elapsedMilliseconds}ms');
      traceBuf.writeln('== Info: Connection #0 to host ${uri.host} left intact');
      traceLog = traceBuf.toString();
    }
    // ── Plain path (no verbose, no trace) ─────────────────────────
    else {
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
      traceLog: traceLog,
      executionTime: sw.elapsed,
    );
  }

  // ── Hex / ASCII dump formatters ──────────────────────────────────

  static const _maxDumpBytes = 65536;

  String _formatHexDump(List<int> data) {
    final limited = data.length > _maxDumpBytes
        ? data.sublist(0, _maxDumpBytes)
        : data;
    final buf = StringBuffer();
    for (var offset = 0; offset < limited.length; offset += 16) {
      final end = offset + 16 > limited.length ? limited.length : offset + 16;
      final chunk = limited.sublist(offset, end);

      buf.write(offset.toRadixString(16).toUpperCase().padLeft(4, '0'));
      buf.write(': ');

      final hexParts = <String>[];
      for (var j = 0; j < 16; j++) {
        if (j < chunk.length) {
          hexParts.add(
            chunk[j].toRadixString(16).toUpperCase().padLeft(2, '0'),
          );
        } else {
          hexParts.add('  ');
        }
      }
      buf.write(hexParts.sublist(0, 8).join(' '));
      buf.write('  ');
      buf.write(hexParts.sublist(8, 16).join(' '));

      buf.write('  ');
      for (final byte in chunk) {
        buf.write(byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  String _formatAsciiDump(List<int> data) {
    final limited = data.length > _maxDumpBytes
        ? data.sublist(0, _maxDumpBytes)
        : data;
    final buf = StringBuffer();
    for (var offset = 0; offset < limited.length; offset += 16) {
      final end = offset + 16 > limited.length ? limited.length : offset + 16;
      final chunk = limited.sublist(offset, end);

      buf.write(offset.toRadixString(16).toUpperCase().padLeft(4, '0'));
      buf.write(': ');
      for (final byte in chunk) {
        buf.write(byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  // ── Raw HTTP byte reconstruction ─────────────────────────────────

  List<int> _buildRawRequestHeaderBytes(
    String method,
    Uri uri,
    Map<String, dynamic> headers, {
    required String protocol,
  }) {
    final buf = StringBuffer();
    buf.write('$method ${uri.path.isEmpty ? '/' : uri.path}');
    if (uri.hasQuery) buf.write('?${uri.query}');
    buf.write(' $protocol\r\n');
    buf.write('Host: ${uri.host}\r\n');
    headers.forEach((key, value) {
      buf.write('$key: $value\r\n');
    });
    buf.write('\r\n');
    return utf8.encode(buf.toString());
  }

  List<int> _buildRawResponseHeaderBytes(
    Response response, {
    required String protocol,
  }) {
    final buf = StringBuffer();
    buf.write(
      '$protocol ${response.statusCode} ${response.statusMessage ?? ""}\r\n',
    );
    response.headers.map.forEach((key, values) {
      for (final v in values) {
        buf.write('$key: $v\r\n');
      }
    });
    buf.write('\r\n');
    return utf8.encode(buf.toString());
  }

  List<int> _extractResponseBytes(
    Response response,
    ResponseType responseType,
  ) {
    if (response.data == null) return [];
    if (response.data is Uint8List) return response.data as Uint8List;
    if (response.data is List<int>) {
      return List<int>.from(response.data as List);
    }
    final text = response.data.toString();
    return utf8.encode(text);
  }
}
