import 'dart:convert';

import 'package:curel/domain/models/request_model.dart';
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

  WorkspaceServiceImpl({
    required EnvService envService,
    required ProjectService projectService,
    required RequestService requestService,
  })  : _envService = envService,
        _projectService = projectService,
        _requestService = requestService;

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
        projData as Map<String, dynamic>,
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
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['type'] != null && data['type'] != 'project') {
      throw Exception('this file is a ${data['type']} export, not a project export');
    }
    final counts = await _importProjectData(data);
    return (requests: counts.requests, envs: counts.envs);
  }

  Future<({int requests, int envs})> _importProjectData(
    Map<String, dynamic> proj,
  ) async {
    final projMeta = proj['project'] as Map<String, dynamic>;
    var totalEnvs = 0;
    var totalRequests = 0;

    final newProject = await _projectService.create(
      projMeta['name'] as String,
      description: projMeta['description'] as String?,
    );

    // Import project env
    final envList = proj['environments'] as List?;
    if (envList != null && envList.isNotEmpty) {
      await _envService.importFromJson(
        newProject.id,
        jsonEncode({'active': proj['active_env'], 'environments': envList}),
      );
      totalEnvs += envList.length;
    }

    // Import requests
    final requests = proj['requests'] as List? ?? [];
    for (final reqData in requests) {
      final req = reqData as Map<String, dynamic>;
      final path = req['path'] as String;
      final content = req['content'] as String;

      final sanitized = path.replaceAll('.curl', '');
      final relativePath = await _requestService.createRequest(
        newProject.id,
        sanitized,
        content,
      );
      totalRequests++;

      final metaJson = req['meta'] as Map<String, dynamic>?;
      if (metaJson != null && metaJson.isNotEmpty) {
        try {
          final meta = RequestMeta.fromJson(metaJson);
          await _requestService.updateMeta(newProject.id, relativePath, meta);
        } catch (_) {}
      }
    }

    return (requests: totalRequests, envs: totalEnvs);
  }
}
