import 'package:Curel/data/models/curl_response.dart';
import 'package:curl_parser/curl_parser.dart';
import 'package:dio/dio.dart';

abstract class CurlHttpClient {
  Future<CurlResponse> execute(Curl curl);
}

class DioCurlHttpClient implements CurlHttpClient {
  final Dio _dio;

  DioCurlHttpClient({Dio? dio}) : _dio = dio ?? Dio();

  @override
  Future<CurlResponse> execute(Curl curl) async {
    final response = await _dio.request<String>(
      curl.uri.toString(),
      data: curl.data,
      options: Options(
        method: curl.method,
        headers: curl.headers,
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
