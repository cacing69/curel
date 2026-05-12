import 'dart:convert';
import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

class CurelNativeAdapter implements CollectionAdapter {
  @override
  String get id => 'curel_native';

  @override
  String get name => 'Curel Native';

  @override
  String get icon => 'archive';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content);
      return data['type'] == 'project' || (data['project'] != null && data['requests'] != null);
    } catch (_) {
      return false;
    }
  }

  // ── Import ──────────────────────────────────────────────────────

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;

    final projMeta = data['project'] as Map<String, dynamic>;

    final envs = <ImportedEnv>[];
    final envList = data['environments'] as List? ?? [];
    final activeEnvId = data['active_env'] as String?;

    for (final e in envList) {
      final eMap = e as Map<String, dynamic>;
      envs.add(ImportedEnv(
        name: eMap['name'] as String,
        isActive: eMap['id'] == activeEnvId,
        variables: (eMap['variables'] as List? ?? [])
            .map((v) => EnvVariable.fromJson(v as Map<String, dynamic>))
            .toList(),
      ));
    }

    final requests = <ImportedRequest>[];
    final reqList = data['requests'] as List? ?? [];
    for (final r in reqList) {
      final rMap = r as Map<String, dynamic>;
      requests.add(ImportedRequest(
        path: rMap['path'] as String,
        curlContent: rMap['content'] as String,
        meta: rMap['meta'] != null
            ? RequestMeta.fromJson(rMap['meta'] as Map<String, dynamic>)
            : null,
      ));
    }

    return ImportedCollection(
      name: projMeta['name'] as String,
      description: projMeta['description'] as String?,
      environments: envs,
      requests: requests,
    );
  }

  // ── Export ──────────────────────────────────────────────────────

  @override
  Future<String> export(ExportedProject project) async {
    final envExports = project.environments.map((env) {
      return {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': env.name,
        'variables': env.variables.map((v) => v.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
    }).toList();

    final requestExports = project.requests.map((req) {
      final parts = req.folderPath.isEmpty
          ? [req.displayName]
          : [...req.folderPath.split('/'), req.displayName];
      final path = parts.map(_sanitize).join('/');

      return {
        'path': path,
        'content': req.curlContent,
      };
    }).toList();

    return const JsonEncoder.withIndent('  ').convert({
      'type': 'project',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'project': {
        'id': '',
        'name': project.name,
        if (project.description != null) 'description': project.description,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'mode': 'local',
      },
      'environments': envExports,
      'requests': requestExports,
    });
  }

  String _sanitize(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
