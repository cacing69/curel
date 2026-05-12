import 'dart:convert';

import 'package:curel/domain/adapters/adapter_registry.dart';
import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/services/request_service.dart';

class PreviewResult {
  final String adapterName;
  final ImportedCollection collection;
  PreviewResult({required this.adapterName, required this.collection});
}

abstract class WorkspaceService {
  Future<String> exportWorkspace();
  Future<({int projects, int requests, int envs})> importWorkspace(String json);
  Future<String> exportProject(String projectId);
  Future<String> exportProjectAs(String projectId, String adapterId);
  Future<({int requests, int envs})> importProject(String json, {String? customName});
  Future<({int requests, int envs})> importIntoProject(String json, String projectId);
  Future<PreviewResult?> previewImport(String json);
}

class WorkspaceServiceImpl implements WorkspaceService {
  final EnvService _envService;
  final ProjectService _projectService;
  final RequestService _requestService;
  final AdapterRegistry _adapterRegistry;

  WorkspaceServiceImpl({
    required EnvService envService,
    required ProjectService projectService,
    required RequestService requestService,
    required AdapterRegistry adapterRegistry,
  })  : _envService = envService,
        _projectService = projectService,
        _requestService = requestService,
        _adapterRegistry = adapterRegistry;

  @override
  Future<String> exportWorkspace() async {
    final globalEnv = await _envService.exportToJson(null);

    final projects = await _projectService.getAll();
    final projectExports = <Map<String, dynamic>>[];

    for (final project in projects) {
      projectExports.add(await _exportProjectData(project.id));
    }

    return const JsonEncoder.withIndent('  ').convert({
      'type': 'workspace',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'global_env': jsonDecode(globalEnv),
      'projects': projectExports,
    });
  }

  @override
  Future<String> exportProject(String projectId) async {
    final project = await _projectService.getById(projectId);
    if (project == null) throw Exception('project not found');

    final data = await _exportProjectData(projectId);
    return const JsonEncoder.withIndent('  ').convert({
      'type': 'project',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      ...data,
    });
  }

  @override
  Future<String> exportProjectAs(String projectId, String adapterId) async {
    final project = await _projectService.getById(projectId);
    if (project == null) throw Exception('project not found');

    final adapter = _adapterRegistry.findById(adapterId);
    if (adapter == null) throw Exception('unknown export format');

    final envs = await _buildExportedEnvs(projectId);
    final requests = await _buildExportedRequests(projectId);

    return adapter.export(ExportedProject(
      name: project.name,
      description: project.description,
      environments: envs,
      requests: requests,
    ));
  }

  Future<List<ExportedEnv>> _buildExportedEnvs(String projectId) async {
    final allEnvs = await _envService.getAll(projectId);
    final active = await _envService.getActive(projectId);
    return allEnvs.map((env) => ExportedEnv(
      name: env.name,
      variables: env.variables,
      isActive: env.id == active?.id,
    )).toList();
  }

  Future<List<ExportedRequest>> _buildExportedRequests(String projectId) async {
    final requestItems = await _requestService.listRequests(projectId);
    final requests = <ExportedRequest>[];
    for (final item in requestItems) {
      final content = await _requestService.readCurl(projectId, item.relativePath);
      if (content == null) continue;

      final path = item.relativePath.replaceAll('.curl', '');
      final lastSlash = path.lastIndexOf('/');
      final folderPath = lastSlash > 0 ? path.substring(0, lastSlash) : '';

      requests.add(ExportedRequest(
        displayName: item.displayName,
        folderPath: folderPath,
        curlContent: content,
      ));
    }
    return requests;
  }

  Future<Map<String, dynamic>> _exportProjectData(String projectId) async {
    final project = await _projectService.getById(projectId);
    final envExport = await _envService.exportToJson(projectId);
    final activeEnv = await _envService.getActive(projectId);

    final requestItems = await _requestService.listRequests(projectId);
    final requestExports = <Map<String, dynamic>>[];
    for (final item in requestItems) {
      final content = await _requestService.readCurl(projectId, item.relativePath);
      if (content == null) continue;

      Map<String, dynamic>? meta;
      try {
        meta = (await _requestService.readMeta(projectId, item.relativePath)).toJson();
        if (meta.isEmpty) meta = null;
      } catch (_) {}

      requestExports.add({
        'path': item.relativePath,
        'content': content,
        if (meta != null) 'meta': meta,
      });
    }

    return {
      'project': project!.toJson(),
      'active_env': activeEnv?.id,
      'environments': jsonDecode(envExport)['environments'],
      'requests': requestExports,
    };
  }

  @override
  Future<({int projects, int requests, int envs})> importWorkspace(
    String json,
  ) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['type'] != null && data['type'] != 'workspace') {
      throw Exception('this file is a ${data['type']} export, not a workspace export');
    }
    var totalEnvs = 0;
    var totalProjects = 0;
    var totalRequests = 0;

    // Import global env
    final globalEnvData = data['global_env'];
    if (globalEnvData != null) {
      final globalMap = globalEnvData as Map<String, dynamic>;
      final envList = globalMap['environments'] as List?;
      if (envList != null && envList.isNotEmpty) {
        await _envService.importFromJson(null, jsonEncode(globalMap));
        totalEnvs += envList.length;
      }
    }

    // Import projects
    final projectList = data['projects'] as List? ?? [];
    for (final projData in projectList) {
      final counts = await _importProjectData(
        jsonEncode(projData),
      );
      totalProjects++;
      totalEnvs += counts.envs;
      totalRequests += counts.requests;
    }

    return (
      projects: totalProjects,
      requests: totalRequests,
      envs: totalEnvs,
    );
  }

  @override
  Future<({int requests, int envs})> importProject(String json, {String? customName}) async {
    return _importProjectData(json, customName: customName);
  }

  @override
  Future<PreviewResult?> previewImport(String json) async {
    final adapter = _adapterRegistry.findAdapter(json);
    if (adapter == null) return null;
    final collection = await adapter.convert(json);
    return PreviewResult(adapterName: adapter.name, collection: collection);
  }

  Future<({int requests, int envs})> _importProjectData(String json, {String? customName}) async {
    final adapter = _adapterRegistry.findAdapter(json);
    if (adapter == null) {
      throw Exception('unsupported file format or corrupted data');
    }
    final collection = await adapter.convert(json);
    return _saveImportedCollection(collection, projectId: null, customName: customName);
  }

  @override
  Future<({int requests, int envs})> importIntoProject(
    String json,
    String projectId,
  ) async {
    final adapter = _adapterRegistry.findAdapter(json);
    if (adapter == null) {
      throw Exception('unsupported file format or corrupted data');
    }
    final collection = await adapter.convert(json);
    return _saveImportedCollection(collection, projectId: projectId);
  }

  Future<({int requests, int envs})> _saveImportedCollection(
    ImportedCollection collection, {
    String? projectId,
    String? customName,
  }) async {
    var totalEnvs = 0;
    var totalRequests = 0;

    final targetId = projectId ??
        (await _projectService.create(
          customName ?? collection.name,
          description: collection.description,
        )).id;

    // Import environments
    if (collection.environments.isNotEmpty) {
      String? activeEnvId;
      final List<Environment> envModels = [];

      for (final importedEnv in collection.environments) {
        final env = Environment(
          id: DateTime.now().millisecondsSinceEpoch.toString() + totalEnvs.toString(),
          name: importedEnv.name,
          variables: importedEnv.variables,
          updatedAt: DateTime.now(),
        );
        envModels.add(env);
        if (importedEnv.isActive) activeEnvId = env.id;
        totalEnvs++;
      }

      await _envService.importFromJson(
        targetId,
        jsonEncode({
          'active': activeEnvId ?? envModels.first.id,
          'environments': envModels.map((e) => e.toJson()).toList(),
        }),
      );
    }

    // Import requests
    for (final req in collection.requests) {
      final sanitizedPath = req.path.replaceAll('.curl', '');
      final relativePath = await _requestService.createRequest(
        targetId,
        sanitizedPath,
        req.curlContent,
      );
      totalRequests++;

      if (req.meta != null) {
        await _requestService.updateMeta(targetId, relativePath, req.meta!);
      }
    }

    return (requests: totalRequests, envs: totalEnvs);
  }
}
