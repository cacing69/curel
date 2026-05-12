import 'dart:io';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/sample_model.dart';
import 'package:path/path.dart' as p;

abstract class SampleService {
  Future<List<SampleItem>> listSamples(String projectId, String curlRelativePath);
  Future<SampleMeta?> readMeta(String projectId, String curlRelativePath, String sampleName, String group);
  Future<String?> readBody(String projectId, String curlRelativePath, String sampleName, String group);
  Future<SampleItem> save(
    String projectId,
    String curlRelativePath,
    String name,
    String body,
    int statusCode,
    Map<String, List<String>> headers,
    String? contentType,
  );
  Future<void> delete(String projectId, String curlRelativePath, String sampleName, String group);
}

class FileSystemSampleService implements SampleService {
  final FileSystemService _fs;

  FileSystemSampleService(this._fs);

  Future<String> _samplesDir(String projectId, String curlRelativePath) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final basePath = p.withoutExtension(curlRelativePath);
    return p.join(requestsDir, basePath, 'samples');
  }

  @override
  Future<List<SampleItem>> listSamples(String projectId, String curlRelativePath) async {
    final samplesDir = await _samplesDir(projectId, curlRelativePath);
    if (!await _fs.exists(samplesDir)) return [];

    final entries = await _fs.listFiles(samplesDir);
    final items = <SampleItem>[];

    for (final entry in entries) {
      if (entry is! Directory) continue;
      final groupDir = entry.path;

      final files = await _fs.listFiles(groupDir);
      for (final file in files) {
        if (file is! File || !file.path.endsWith('.meta.json')) continue;
        try {
          final metaContent = await _fs.readFile(file.path);
          final meta = SampleMeta.decode(metaContent);
          final sampleName = p.basenameWithoutExtension(file.path).replaceAll('.meta', '');
          items.add(SampleItem(
            name: sampleName,
            relativePath: p.relative(file.path, from: samplesDir),
            meta: meta,
          ));
        } catch (_) {}
      }
    }

    items.sort((a, b) => b.meta.savedAt.compareTo(a.meta.savedAt));
    return items;
  }

  @override
  Future<SampleMeta?> readMeta(String projectId, String curlRelativePath, String sampleName, String group) async {
    final dir = await _samplesDir(projectId, curlRelativePath);
    final metaPath = p.join(dir, group, '$sampleName.meta.json');
    if (!await _fs.exists(metaPath)) return null;
    final content = await _fs.readFile(metaPath);
    return SampleMeta.decode(content);
  }

  @override
  Future<String?> readBody(String projectId, String curlRelativePath, String sampleName, String group) async {
    final dir = await _samplesDir(projectId, curlRelativePath);
    final bodyPath = p.join(dir, group, '$sampleName.json');
    if (!await _fs.exists(bodyPath)) return null;
    return _fs.readFile(bodyPath);
  }

  @override
  Future<SampleItem> save(
    String projectId,
    String curlRelativePath,
    String name,
    String body,
    int statusCode,
    Map<String, List<String>> headers,
    String? contentType,
  ) async {
    final group = SampleMeta.groupFor(statusCode);
    final dir = await _samplesDir(projectId, curlRelativePath);
    final sampleDir = p.join(dir, group);

    final sanitizedName = name.trim().replaceAll(RegExp(r'[^\w\-.]'), '_');

    final bodyPath = p.join(sampleDir, '$sanitizedName.json');
    final metaPath = p.join(sampleDir, '$sanitizedName.meta.json');

    final meta = SampleMeta(
      name: name,
      statusCode: statusCode,
      statusCodeGroup: group,
      headers: headers,
      contentType: contentType,
    );

    await _fs.writeFile(bodyPath, body);
    await _fs.writeFile(metaPath, SampleMeta.encode(meta));

    return SampleItem(name: sanitizedName, relativePath: p.join(group, sanitizedName), meta: meta);
  }

  @override
  Future<void> delete(String projectId, String curlRelativePath, String sampleName, String group) async {
    final dir = await _samplesDir(projectId, curlRelativePath);
    final bodyPath = p.join(dir, group, '$sampleName.json');
    final metaPath = p.join(dir, group, '$sampleName.meta.json');
    await _fs.deleteFile(bodyPath);
    await _fs.deleteFile(metaPath);
  }
}
