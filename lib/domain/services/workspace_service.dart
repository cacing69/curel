import 'dart:convert';

import 'package:curel/domain/adapters/adapter_registry.dart';
import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/services/request_service.dart';

abstract class WorkspaceService {
  Future<String> exportWorkspace();
  Future<({int projects, int requests, int envs})> importWorkspace(String json);
  Future<String> exportProject(String projectId);
  Future<({int requests, int envs})> importProject(String json);
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
  Future<({int requests, int envs})> importProject(String json) async {
    return _importProjectData(json);
  }

  Future<({int requests, int envs})> _importProjectData(String json) async {
    // 1. Detect adapter
    final adapter = _adapterRegistry.findAdapter(json);
    if (adapter == null) {
      throw Exception('unsupported file format or corrupted data');
    }

    // 2. Convert to ImportedCollection
    final collection = await adapter.convert(json);

    // 3. Save to Filesystem
    return _saveImportedCollection(collection);
  }

  Future<({int requests, int envs})> _saveImportedCollection(
    ImportedCollection collection,
  ) async {
    var totalEnvs = 0;
    var totalRequests = 0;

    // Create project
    final newProject = await _projectService.create(
      collection.name,
      description: collection.description,
    );

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
        newProject.id,
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
        newProject.id,
        sanitizedPath,
        req.curlContent,
      );
      totalRequests++;

      if (req.meta != null) {
        await _requestService.updateMeta(newProject.id, relativePath, req.meta!);
      }
    }

    return (requests: totalRequests, envs: totalEnvs);
  }
}
