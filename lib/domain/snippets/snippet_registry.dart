import 'package:curel/domain/snippets/snippet_generator.dart';
import 'package:curel/domain/snippets/generators/curl_generator.dart';
import 'package:curel/domain/snippets/generators/python_requests_generator.dart';
import 'package:curel/domain/snippets/generators/js_fetch_generator.dart';
import 'package:curel/domain/snippets/generators/go_generator.dart';
import 'package:curel/domain/snippets/generators/dart_http_generator.dart';
import 'package:curel/domain/snippets/generators/php_generator.dart';
import 'package:curel/domain/snippets/generators/java_okhttp_generator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SnippetRegistry {
  final List<SnippetGenerator> _generators = [];

  SnippetRegistry() {
    _register(CurlSnippetGenerator());
    _register(PythonRequestsGenerator());
    _register(JsFetchGenerator());
    _register(GoGenerator());
    _register(DartHttpGenerator());
    _register(PhpGenerator());
    _register(JavaOkHttpGenerator());
  }

  void _register(SnippetGenerator generator) {
    _generators.add(generator);
  }

  List<SnippetGenerator> get available => List.unmodifiable(_generators);

  SnippetGenerator? findById(String id) {
    try {
      return _generators.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }
}

final snippetRegistryProvider = Provider<SnippetRegistry>((ref) => SnippetRegistry());
