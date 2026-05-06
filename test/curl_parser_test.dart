import 'package:flutter_test/flutter_test.dart';
import 'package:curel/domain/services/curl_parser_service.dart';

void main() {
  group('parseCurl', () {
    test('parses basic curl without unsupported flags', () {
      final curl = parseCurl('curl https://example.com');

      expect(curl.method, 'GET');
      expect(curl.uri.toString(), 'https://example.com');
    });

    test('parses curl with -X and headers', () {
      final curl = parseCurl(
        "curl -X POST 'https://api.example.com/data' "
        "-H 'Content-Type: application/json'",
      );

      expect(curl.method, 'POST');
      expect(curl.uri.toString(), 'https://api.example.com/data');
      expect(curl.headers, containsPair('Content-Type', 'application/json'));
    });

    test('strips -s (silent) flag', () {
      final curl = parseCurl('curl -s https://example.com');

      expect(curl.method, 'GET');
      expect(curl.uri.toString(), 'https://example.com');
    });

    test('strips -sS (combined silent + show-error) flag', () {
      final input =
          "curl -sS -X GET \\\n"
          "  'https://example.com/path/x-id/202' \\\n"
          "  -H 'Authorization: Bearer xx.yy.zz' \\\n"
          "  -H 'Accept: application/json'";

      final curl = parseCurl(input);

      expect(curl.method, 'GET');
      expect(curl.uri.toString(), 'https://example.com/path/x-id/202');
      expect(
        curl.headers,
        containsPair('Authorization', 'Bearer xx.yy.zz'),
      );
      expect(curl.headers, containsPair('Accept', 'application/json'));
    });

    test('strips --compressed flag', () {
      final curl = parseCurl(
        "curl --compressed 'https://example.com'",
      );

      expect(curl.uri.toString(), 'https://example.com');
    });

    test('strips -v (verbose) flag', () {
      final curl = parseCurl(
        "curl -v -X DELETE 'https://example.com/resource/1'",
      );

      expect(curl.method, 'DELETE');
      expect(curl.uri.toString(), 'https://example.com/resource/1');
    });

    test('strips -sSv combined flags while keeping -X', () {
      final curl = parseCurl(
        "curl -sSv -X PUT 'https://example.com'",
      );

      expect(curl.method, 'PUT');
      expect(curl.uri.toString(), 'https://example.com');
    });

    test('strips -o with its value', () {
      final curl = parseCurl(
        "curl -o output.txt 'https://example.com/file'",
      );

      expect(curl.uri.toString(), 'https://example.com/file');
    });

    test('parses multiline curl with backslash continuation', () {
      final input =
          "curl -X GET \\\n"
          "  'https://example.com/api' \\\n"
          "  -H 'Accept: application/json'";

      final curl = parseCurl(input);

      expect(curl.method, 'GET');
      expect(curl.uri.toString(), 'https://example.com/api');
      expect(curl.headers, containsPair('Accept', 'application/json'));
    });

    test('parses curl with data flag', () {
      final curl = parseCurl(
        "curl -X POST 'https://example.com' -d '{\"key\":\"value\"}'",
      );

      expect(curl.method, 'POST');
      expect(curl.data, '{"key":"value"}');
    });
  });
}
