import 'dart:convert';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _keyProjectList = 'project_list';
const _keyActiveProject = 'active_project';
const _defaultProjectName = 'default';

abstract class ProjectService {
  Future<List<Project>> getAll();
  Future<Project?> getById(String id);
  Future<Project> create(String name, {String? description});
  Future<void> update(Project project);
  Future<void> delete(String id);
  Future<String?> getActiveProjectId();
  Future<void> setActiveProject(String? id);
  Future<Project?> getActiveProject();
  Future<Project> ensureDefaultProject();
}

class FilesystemProjectService implements ProjectService {
  final FileSystemService _fs;
  SharedPreferences? _prefs;

  FilesystemProjectService(this._fs);

  Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<Project>> getAll() async {
    final prefs = await _instance;
    final raw = prefs.getString(_keyProjectList);
    if (raw == null) return [];
    return Project.decodeList(raw);
  }

  @override
  Future<Project?> getById(String id) async {
    final all = await getAll();
    return all.where((p) => p.id == id).firstOrNull;
  }

  @override
  Future<Project> create(String name, {String? description}) async {
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _fs.createProjectStructure(project.id);

    final projectJsonPath = await _getProjectJsonPath(project.id);
    await _fs.writeFile(projectJsonPath, jsonEncode(project.toJson()));

    final all = await getAll();
    all.add(project);
    await _saveAll(all);

    return project;
  }

  @override
  Future<void> update(Project project) async {
    final updated = project.copyWith(updatedAt: DateTime.now());

    final projectJsonPath = await _getProjectJsonPath(updated.id);
    await _fs.writeFile(projectJsonPath, jsonEncode(updated.toJson()));

    final all = await getAll();
    final idx = all.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      all[idx] = updated;
    }
    await _saveAll(all);
  }

  @override
  Future<void> delete(String id) async {
    final all = await getAll();
    final project = all.where((p) => p.id == id).firstOrNull;

    if (project != null) {
      all.removeWhere((p) => p.id == id);
      await _saveAll(all);
      await _fs.deleteProjectDir(id);

      final prefs = await _instance;
      if (prefs.getString(_keyActiveProject) == id) {
        await prefs.remove(_keyActiveProject);
      }
    }
  }

  @override
  Future<String?> getActiveProjectId() async {
    final prefs = await _instance;
    final id = prefs.getString(_keyActiveProject);
    if (id == null) return null;
    final project = await getById(id);
    return project?.id;
  }

  @override
  Future<void> setActiveProject(String? id) async {
    final prefs = await _instance;
    if (id == null) {
      await prefs.remove(_keyActiveProject);
    } else {
      await prefs.setString(_keyActiveProject, id);
    }
  }

  @override
  Future<Project?> getActiveProject() async {
    final id = await getActiveProjectId();
    if (id == null) return null;
    return getById(id);
  }

  Future<String> _getProjectJsonPath(String projectId) async {
    final projectDir = await _fs.getProjectDir(projectId);
    return p.join(projectDir, 'curel.json');
  }

  Future<void> _saveAll(List<Project> projects) async {
    final prefs = await _instance;
    await prefs.setString(_keyProjectList, Project.encodeList(projects));
  }

  @override
  Future<Project> ensureDefaultProject() async {
    final all = await getAll();
    final existing = all.where((p) => p.name == _defaultProjectName).firstOrNull;
    if (existing != null) {
      final activeId = await getActiveProjectId();
      if (activeId == null) await setActiveProject(existing.id);
      return existing;
    }

    final project = await create(_defaultProjectName);
    await setActiveProject(project.id);
    return project;
  }
}
