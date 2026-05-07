import 'package:curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';
import 'package:dio/dio.dart';

abstract class CurlHttpClient {
  Future<CurlResponse> execute(Curl curl);
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
  Future<CurlResponse> execute(Curl curl) async {
    final headers = <String, dynamic>{...?curl.headers};
    headers['User-Agent'] = _userAgent;
    final response = await _dio.request<String>(
      curl.uri.toString(),
      data: curl.data,
      options: Options(
        method: curl.method,
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    return CurlResponse(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage ?? '',
      headers: response.headers.map,
      body: response.data,
    );
  }
}
