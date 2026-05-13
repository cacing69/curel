import 'package:curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';

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

  Future<CurlResponse?> executeRaw(String curlCommand, {
    bool verbose = false,
    bool trace = false,
    bool traceAscii = false,
  });
}
