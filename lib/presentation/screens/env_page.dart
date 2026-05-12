import 'dart:convert';
import 'dart:io';

import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _EnvScope { project, global }

class EnvPage extends ConsumerStatefulWidget {
  final String? projectId;

  EnvPage({this.projectId, super.key});

  @override
  ConsumerState<EnvPage> createState() => _EnvPageState();
}

class _EnvPageState extends ConsumerState<EnvPage> {
  var _scope = _EnvScope.project;
  List<Environment> _envs = [];
  String? _activeId;
  var _loading = true;
  final _values = <String, String>{};

  String? get _scopeProjectId =>
      _scope == _EnvScope.project ? widget.projectId : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Environment? get _globalEnv =>
      _scope == _EnvScope.global && _envs.length == 1 ? _envs.first : null;

  Future<void> _load() async {
    final scopeId = _scopeProjectId;
    var envs = await ref.read(envServiceProvider).getAll(scopeId);

    if (_scope == _EnvScope.global && envs.isEmpty) {
      final env = await ref.read(envServiceProvider).create(null, 'default');
      await ref.read(envServiceProvider).setActive(null, env.id);
      envs = [env];
    }

    final active = await ref.read(envServiceProvider).getActive(scopeId);
    final values = <String, String>{};
    for (final env in envs) {
      for (final v in env.variables) {
        final val = await ref.read(envServiceProvider).getValue(env, v.key);
        if (val != null) values['${env.id}_${v.key}'] = val;
      }
    }
    if (mounted) {
      setState(() {
        _envs = envs;
        _activeId = active?.id;
        _values
          ..clear()
          ..addAll(values);
        _loading = false;
      });
    }
  }

  void _switchScope(_EnvScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _loading = true;
    });
    _load();
  }

  Future<void> _setActive(String id) async {
    await ref.read(envServiceProvider).setActive(_scopeProjectId, id);
    setState(() => _activeId = id);
  }

  Future<void> _createEnv() async {
    final name = await _showNameDialog('new environment');
    if (name == null || name.trim().isEmpty) return;
    final env = await ref.read(envServiceProvider).create(_scopeProjectId, name.trim());
    await _setActive(env.id);
    await _load();
  }

  Future<void> _renameEnv(String envId) async {
    final env = _envs.where((e) => e.id == envId).firstOrNull;
    if (env == null) return;
    final name = await _showNameDialog('rename', initial: env.name);
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(envServiceProvider).save(
        _scopeProjectId,
        env.copyWith(name: name.trim()),
      );
      await _load();
    } on FileSystemException catch (e) {
      if (!mounted) return;
      if (e.message == 'Target already exists') {
        showTerminalToast(context, 'name already exists');
      } else {
        showTerminalToast(context, 'error: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      showTerminalToast(context, 'error: $e');
    }
  }

  Future<void> _duplicateEnv(String envId) async {
    final env = _envs.where((e) => e.id == envId).firstOrNull;
    if (env == null) return;
    final copy = ref.read(envServiceProvider).duplicate(env);
    await ref.read(envServiceProvider).save(_scopeProjectId, copy);
    await _load();
  }

  Future<void> _deleteEnv(String id) async {
    await ref.read(envServiceProvider).delete(_scopeProjectId, id);
    if (_activeId == id) _activeId = null;
    await _load();
  }

  Future<void> _addVariable(Environment env) async {
    final result = await _showVarDialog('new variable');
    if (result == null) return;
    final vars = [
      ...env.variables,
      EnvVariable(key: result.key, sensitive: result.sensitive),
    ];
    await ref.read(envServiceProvider).save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await ref.read(envServiceProvider).setValue(env, result.key, result.value);
    await _load();
  }

  Future<void> _editVariable(Environment env, int index) async {
    final v = env.variables[index];
    final currentValue = await ref.read(envServiceProvider).getValue(env, v.key);
    final result = await _showVarDialog(
      'edit variable',
      initialKey: v.key,
      initialValue: currentValue ?? '',
      initialSensitive: v.sensitive,
    );
    if (result == null) return;
    if (result.key != v.key) {
      await ref.read(envServiceProvider).setValue(env, v.key, '');
    }
    final vars = [...env.variables];
    vars[index] = EnvVariable(key: result.key, sensitive: result.sensitive);
    await ref.read(envServiceProvider).save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await ref.read(envServiceProvider).setValue(env, result.key, result.value);
    await _load();
  }

  Future<void> _deleteVariable(Environment env, int index) async {
    final v = env.variables[index];
    await ref.read(envServiceProvider).setValue(env, v.key, '');
    final vars = [...env.variables]..removeAt(index);
    await ref.read(envServiceProvider).save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await _load();
  }

  Future<void> _export() async {
    final json = await ref.read(envServiceProvider).exportToJson(_scopeProjectId);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'export env',
        fileName: 'curel-env.json',
        bytes: utf8.encode(json),
      );
      if (path != null && mounted) {
        showTerminalToast(context, 'exported');
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      final json = utf8.decode(bytes);
      await ref.read(envServiceProvider).importFromJson(_scopeProjectId, json);
      await _load();
      if (mounted) showTerminalToast(context, 'imported');
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────

  Future<String?> _showNameDialog(String action, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,

        title: Text(
          action,
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: TColors.green,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'name',
              hintStyle: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(
              'ok',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<({String key, String value, bool sensitive})?> _showVarDialog(
    String action, {
    String? initialKey,
    String? initialValue,
    bool initialSensitive = false,
  }) {
    final keyCtrl = TextEditingController(text: initialKey ?? '');
    final valCtrl = TextEditingController(text: initialValue ?? '');
    var sensitive = initialSensitive;
    return showDialog<({String key, String value, bool sensitive})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: TColors.background,
          elevation: 0,

          title: Text(
            action,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: TColors.surface,
                child: TextField(
                  controller: keyCtrl,
                  autofocus: initialKey == null,
                  cursorColor: TColors.green,
                  style: TextStyle(
                    color: TColors.cyan,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'KEY',
                    hintStyle: TextStyle(
                      color: TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: TColors.surface,
                child: TextField(
                  controller: valCtrl,
                  autofocus: initialKey != null,
                  cursorColor: TColors.green,
                  style: TextStyle(
                    color: TColors.foreground,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'value',
                    hintStyle: TextStyle(
                      color: TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(height: 8),
              GestureDetector(
                onTap: () => setDialogState(() => sensitive = !sensitive),
                child: Row(
                  children: [
                    Icon(
                      sensitive
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                      color: sensitive ? TColors.green : TColors.mutedText,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'sensitive',
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'cancel',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final k = keyCtrl.text.trim();
                final v = valCtrl.text.trim();
                if (k.isEmpty) return;
                Navigator.of(ctx).pop((key: k, value: v, sensitive: sensitive));
              },
              child: Text(
                'ok',
                style: TextStyle(color: TColors.green, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : _scope == _EnvScope.global
                  ? _buildGlobalList()
                  : _envs.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'env',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: () => _switchScope(_EnvScope.project),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: _scope == _EnvScope.project
                  ? TColors.green.withValues(alpha: 0.15)
                  : Colors.transparent,
              child: Text(
                'project',
                style: TextStyle(
                  color: _scope == _EnvScope.project
                      ? TColors.green
                      : TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ),
          ),
          SizedBox(width: 4),
          GestureDetector(
            onTap: () => _switchScope(_EnvScope.global),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: _scope == _EnvScope.global
                  ? TColors.purple.withValues(alpha: 0.15)
                  : Colors.transparent,
              child: Text(
                'global',
                style: TextStyle(
                  color: _scope == _EnvScope.global
                      ? TColors.purple
                      : TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        'no env yet',
        style: TextStyle(
          color: TColors.mutedText.withValues(alpha: 0.5),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildGlobalList() {
    final env = _globalEnv;
    if (env == null) return _buildEmpty();

    if (env.variables.isEmpty) {
      return Center(
        child: Text(
          'no variables yet',
          style: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: env.variables.length,
      itemBuilder: (_, i) {
        final v = env.variables[i];
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: i.isEven ? TColors.background : TColors.surface,
          child: Row(
            children: [
              Text(
                '<<${v.key}>>',
                style: TextStyle(
                  color: TColors.purple,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.sensitive
                      ? '***'
                      : (_values['${env.id}_${v.key}'] ?? ''),
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _editVariable(env, i),
                child: Icon(Icons.edit, size: 12, color: TColors.mutedText),
              ),
              SizedBox(width: 8),
              GestureDetector(
                onTap: () => _deleteVariable(env, i),
                child: Icon(Icons.delete, size: 12, color: TColors.red),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _envs.length,
      separatorBuilder: (_, _) => Container(height: 1, color: TColors.border),
      itemBuilder: (_, i) => _buildEnvTile(_envs[i]),
    );
  }

  Widget _buildEnvTile(Environment env) {
    final isActive = env.id == _activeId;
    return Container(
      color: TColors.surface,
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: TColors.mutedText,
        collapsedIconColor: TColors.mutedText,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => _setActive(env.id),
              child: Icon(
                isActive
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: isActive ? TColors.green : TColors.mutedText,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                env.name,
                style: TextStyle(
                  color: isActive ? TColors.green : TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${env.variables.length}',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            SizedBox(width: 8),
            _popupMenu(env),
          ],
        ),
        children: [
          ...env.variables.asMap().entries.map((entry) {
            final idx = entry.key;
            final v = entry.value;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: TColors.background,
              child: Row(
                children: [
                  Text(
                    '<<${v.key}>>',
                    style: TextStyle(
                      color: TColors.purple,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      v.sensitive
                          ? '***'
                          : (_values['${env.id}_${v.key}'] ?? ''),
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _editVariable(env, idx),
                    child: Icon(Icons.edit, size: 12, color: TColors.mutedText),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deleteVariable(env, idx),
                    child: Icon(Icons.delete, size: 12, color: TColors.red),
                  ),
                ],
              ),
            );
          }),
          Container(
            color: TColors.background,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: GestureDetector(
              onTap: () => _addVariable(env),
              child: Text(
                '+ add var',
                style: TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _popupMenu(Environment env) {
    return GestureDetector(
      onTapDown: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<int>(
          context: context,
          elevation: 0,
          position: RelativeRect.fromLTRB(
            offset.dx,
            details.globalPosition.dy,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            PopupMenuItem(
              value: 0,
              height: 36,
              child: _menuItem(Icons.edit, 'rename'),
            ),
            PopupMenuItem(
              value: 1,
              height: 36,
              child: _menuItem(Icons.copy, 'duplicate'),
            ),
            PopupMenuItem(
              value: 2,
              height: 36,
              child: _menuItem(Icons.delete, 'delete'),
            ),
          ],
        ).then((value) {
          if (value == 0) _renameEnv(env.id);
          if (value == 1) _duplicateEnv(env.id);
          if (value == 2) _deleteEnv(env.id);
        });
      },
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 6),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: TColors.mutedText),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final isGlobal = _scope == _EnvScope.global;
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (isGlobal)
            TermButton(
              icon: Icons.add,
              label: 'add var',
              onTap: _globalEnv != null
                  ? () => _addVariable(_globalEnv!)
                  : null,
              accent: true,
            )
          else
            TermButton(
              icon: Icons.add,
              label: 'new',
              onTap: _createEnv,
              accent: true,
            ),
          Spacer(),
          TermButton(icon: Icons.upload_file, label: 'import', onTap: _import),
          SizedBox(width: 6),
          TermButton(icon: Icons.download, label: 'export', onTap: _export),
        ],
      ),
    );
  }
}
