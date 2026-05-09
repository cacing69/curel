import 'dart:convert';

import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

enum _EnvScope { project, global }

class EnvPage extends StatefulWidget {
  final EnvService envService;
  final String? projectId;

  const EnvPage({required this.envService, this.projectId, super.key});

  @override
  State<EnvPage> createState() => _EnvPageState();
}

class _EnvPageState extends State<EnvPage> {
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

  Future<void> _load() async {
    final scopeId = _scopeProjectId;
    final envs = await widget.envService.getAll(scopeId);
    final active = await widget.envService.getActive(scopeId);
    final values = <String, String>{};
    for (final env in envs) {
      for (final v in env.variables) {
        final val = await widget.envService.getValue(env, v.key);
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
    await widget.envService.setActive(_scopeProjectId, id);
    setState(() => _activeId = id);
  }

  Future<void> _createEnv() async {
    final name = await _showNameDialog('new environment');
    if (name == null || name.trim().isEmpty) return;
    final env = await widget.envService.create(_scopeProjectId, name.trim());
    await _setActive(env.id);
    await _load();
  }

  Future<void> _renameEnv(Environment env) async {
    final name = await _showNameDialog('rename', initial: env.name);
    if (name == null || name.trim().isEmpty) return;
    await widget.envService.save(
      _scopeProjectId,
      env.copyWith(name: name.trim()),
    );
    await _load();
  }

  Future<void> _duplicateEnv(Environment env) async {
    final copy = widget.envService.duplicate(env);
    await widget.envService.save(_scopeProjectId, copy);
    await _load();
  }

  Future<void> _deleteEnv(String id) async {
    await widget.envService.delete(_scopeProjectId, id);
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
    await widget.envService.save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await widget.envService.setValue(env, result.key, result.value);
    await _load();
  }

  Future<void> _editVariable(Environment env, int index) async {
    final v = env.variables[index];
    final currentValue = await widget.envService.getValue(env, v.key);
    final result = await _showVarDialog(
      'edit variable',
      initialKey: v.key,
      initialValue: currentValue ?? '',
      initialSensitive: v.sensitive,
    );
    if (result == null) return;
    if (result.key != v.key) {
      await widget.envService.setValue(env, v.key, '');
    }
    final vars = [...env.variables];
    vars[index] = EnvVariable(key: result.key, sensitive: result.sensitive);
    await widget.envService.save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await widget.envService.setValue(env, result.key, result.value);
    await _load();
  }

  Future<void> _deleteVariable(Environment env, int index) async {
    final v = env.variables[index];
    await widget.envService.setValue(env, v.key, '');
    final vars = [...env.variables]..removeAt(index);
    await widget.envService.save(
      _scopeProjectId,
      env.copyWith(variables: vars),
    );
    await _load();
  }

  Future<void> _export() async {
    final json = await widget.envService.exportToJson(_scopeProjectId);
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
      await widget.envService.importFromJson(_scopeProjectId, json);
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
        backgroundColor: TColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),

        title: Text(
          action,
          style: const TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: TColors.green,
          style: const TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: 'name',
            hintStyle: const TextStyle(
              color: TColors.mutedText,
              fontFamily: 'monospace',
            ),
            border: InputBorder.none,
            filled: true, // Wajib true agar fillColor aktif
            fillColor: const Color(
              0xFF1A1A1A,
            ), // Ganti dengan TColors.inputBg atau warna pilihan Anda
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ), // Agar teks tidak menempel ke pinggir
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
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
          backgroundColor: TColors.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,

          title: Text(
            action,
            style: const TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                autofocus: initialKey == null,
                cursorColor: TColors.green,
                style: const TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'KEY',
                  hintStyle: const TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                  ),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: TColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valCtrl,
                autofocus: initialKey != null,
                cursorColor: TColors.green,
                style: const TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'value',
                  hintStyle: const TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                  ),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: TColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                    const SizedBox(width: 8),
                    const Text(
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
              child: const Text(
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
              child: const Text(
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: TColors.green,
                        strokeWidth: 2,
                      ),
                    )
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'env',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _switchScope(_EnvScope.project),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _switchScope(_EnvScope.global),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            const SizedBox(width: 8),
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
              style: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            _popupMenu(env),
          ],
        ),
        children: [
          ...env.variables.asMap().entries.map((entry) {
            final idx = entry.key;
            final v = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: TColors.background,
              child: Row(
                children: [
                  Text(
                    '<<${v.key}>>',
                    style: const TextStyle(
                      color: TColors.purple,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      v.sensitive
                          ? '***'
                          : (_values['${env.id}_${v.key}'] ?? ''),
                      style: const TextStyle(
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
                  const SizedBox(width: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: GestureDetector(
              onTap: () => _addVariable(env),
              child: const Text(
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
          shape: const RoundedRectangleBorder(),
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
          if (value == 0) _renameEnv(env);
          if (value == 1) _duplicateEnv(env);
          if (value == 2) _deleteEnv(env.id);
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: TColors.mutedText),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: TColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TermButton(
            icon: Icons.add,
            label: 'new',
            onTap: _createEnv,
            accent: true,
          ),
          const Spacer(),
          TermButton(icon: Icons.upload_file, label: 'import', onTap: _import),
          const SizedBox(width: 6),
          TermButton(icon: Icons.download, label: 'export', onTap: _export),
        ],
      ),
    );
  }
}
