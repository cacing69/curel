import 'package:curel/domain/models/cookie_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CookieJarDialog extends ConsumerStatefulWidget {
  final String projectId;

  const CookieJarDialog({required this.projectId, super.key});

  @override
  ConsumerState<CookieJarDialog> createState() => _CookieJarDialogState();
}

class _CookieJarDialogState extends ConsumerState<CookieJarDialog> {
  List<CookieJar> _jars = [];
  CookieJar? _activeJar;
  bool _loading = true;
  String? _editingCookie; // cookie name being edited
  final _nameCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  bool _secure = false;
  bool _httpOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _domainCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(cookieJarServiceProvider);
    final jars = await service.listJars(widget.projectId);
    final active = await service.getActiveJar(widget.projectId);

    if (!mounted) return;
    setState(() {
      _jars = jars;
      _activeJar = active;
      _loading = false;
    });
  }

  Future<void> _switchJar(String jarName) async {
    final service = ref.read(cookieJarServiceProvider);
    await service.setActiveJar(widget.projectId, jarName);
    await _load();
  }

  Future<void> _createJar() async {
    final name = await _showNameDialog('new jar');
    if (name == null || name.isEmpty) return;

    final service = ref.read(cookieJarServiceProvider);
    await service.createJar(widget.projectId, name);
    await service.setActiveJar(widget.projectId, name);
    await _load();
  }

  Future<void> _deleteJar(String jarName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('delete jar', style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text('delete cookie jar "$jarName"?', style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel', style: TextStyle(color: TColors.mutedText, fontSize: 12))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('delete', style: TextStyle(color: TColors.red, fontSize: 12))),
        ],
      ),
    );
    if (confirm != true) return;

    final service = ref.read(cookieJarServiceProvider);
    await service.deleteJar(widget.projectId, jarName);
    await _load();
  }

  void _startAddCookie() {
    setState(() {
      _editingCookie = null;
      _nameCtrl.clear();
      _valueCtrl.clear();
      _domainCtrl.clear();
      _pathCtrl.text = '/';
      _secure = false;
      _httpOnly = false;
    });
  }

  void _startEditCookie(CookieEntry cookie) {
    setState(() {
      _editingCookie = cookie.name;
      _nameCtrl.text = cookie.name;
      _valueCtrl.text = cookie.value;
      _domainCtrl.text = cookie.domain ?? '';
      _pathCtrl.text = cookie.path ?? '/';
      _secure = cookie.secure;
      _httpOnly = cookie.httpOnly;
    });
  }

  Future<void> _saveCookie() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final service = ref.read(cookieJarServiceProvider);
    await service.addCookie(widget.projectId, CookieEntry(
      name: name,
      value: _valueCtrl.text.trim(),
      domain: _domainCtrl.text.trim().isNotEmpty ? _domainCtrl.text.trim() : null,
      path: _pathCtrl.text.trim().isNotEmpty ? _pathCtrl.text.trim() : null,
      secure: _secure,
      httpOnly: _httpOnly,
    ));

    setState(() => _editingCookie = null);
    await _load();
  }

  Future<void> _removeCookie(String cookieName) async {
    final service = ref.read(cookieJarServiceProvider);
    await service.removeCookie(widget.projectId, cookieName);
    await _load();
  }

  Future<void> _clearAllCookies() async {
    if (_activeJar == null) return;
    final service = ref.read(cookieJarServiceProvider);
    await service.saveJar(widget.projectId, _activeJar!.copyWith(cookies: []));
    await _load();
  }

  Future<void> _importNetscape() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String content;
      if (file.path != null) {
        content = await ref.read(fileSystemProvider).readFile(file.path!);
      } else if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else {
        return;
      }

      final service = ref.read(cookieJarServiceProvider);
      await service.importNetscape(widget.projectId, content);
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('cookies imported'), backgroundColor: TColors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('import failed: $e'), backgroundColor: TColors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          children: [
            _buildHeader(),
            Container(height: 1, color: TColors.border),
            _loading
                ? Expanded(child: Center(child: TerminalLoader()))
                : Expanded(child: _buildBody()),
            Container(height: 1, color: TColors.border),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: TColors.surface,
      child: Row(
        children: [
          Icon(Icons.cookie_outlined, size: 16, color: TColors.purple),
          SizedBox(width: 8),
          Text(
            'cookie jars',
            style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Spacer(),
          if (_jars.length > 1)
            GestureDetector(
              onTap: () => _deleteJar(_activeJar!.name),
              child: Icon(Icons.delete_outline, size: 14, color: TColors.mutedText),
            ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.close, size: 16, color: TColors.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Jar tabs
        if (_jars.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._jars.map((jar) {
                    final isActive = _activeJar?.name == jar.name;
                    return Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: FlatTab(
                        label: jar.name,
                        selected: isActive,
                        onTap: () => _switchJar(jar.name),
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: _createJar,
                    child: Icon(Icons.add, size: 14, color: TColors.mutedText),
                  ),
                ],
              ),
            ),
          ),
        Container(height: 1, color: TColors.border),
        // Cookie form or list
        if (_editingCookie != null)
          Expanded(child: _buildCookieForm())
        else
          Expanded(child: _buildCookieList()),
      ],
    );
  }

  Widget _buildCookieList() {
    if (_activeJar == null || _activeJar!.cookies.isEmpty) {
      return Center(
        child: Text(
          _jars.isEmpty ? 'no jars yet — create one' : 'no cookies in this jar',
          style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: _activeJar!.cookies.length,
      separatorBuilder: (_, _) => Container(height: 1, color: TColors.border),
      itemBuilder: (_, i) {
        final cookie = _activeJar!.cookies[i];
        return _buildCookieRow(cookie);
      },
    );
  }

  Widget _buildCookieRow(CookieEntry cookie) {
    final isExpired = cookie.isExpired();
    return GestureDetector(
      onTap: () => _startEditCookie(cookie),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isExpired ? TColors.red.withValues(alpha: 0.05) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          cookie.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: TColors.cyan, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (cookie.secure) ...[
                        SizedBox(width: 6),
                        Icon(Icons.lock, size: 10, color: TColors.orange),
                      ],
                      if (cookie.httpOnly) ...[
                        SizedBox(width: 4),
                        Icon(Icons.shield, size: 10, color: TColors.mutedText),
                      ],
                      if (isExpired) ...[
                        SizedBox(width: 6),
                        Text('expired', style: TextStyle(color: TColors.red, fontFamily: 'monospace', fontSize: 9)),
                      ],
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    cookie.value.length > 40 ? '${cookie.value.substring(0, 40)}...' : cookie.value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 10),
                  ),
                  if (cookie.domain != null)
                    Text(
                      cookie.domain!,
                      style: TextStyle(color: TColors.comment, fontFamily: 'monospace', fontSize: 9),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _removeCookie(cookie.name),
              child: Icon(Icons.close, size: 12, color: TColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCookieForm() {
    return Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingCookie == null ? 'add cookie' : 'edit cookie',
            style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _field('name', _nameCtrl, enabled: _editingCookie == null),
          SizedBox(height: 8),
          _field('value', _valueCtrl),
          SizedBox(height: 8),
          _field('domain', _domainCtrl, hint: '.example.com'),
          SizedBox(height: 8),
          _field('path', _pathCtrl, hint: '/'),
          SizedBox(height: 8),
          Row(
            children: [
              _checkbox('secure', _secure, (v) => setState(() => _secure = v)),
              SizedBox(width: 16),
              _checkbox('httponly', _httpOnly, (v) => setState(() => _httpOnly = v)),
            ],
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TermButton(
                label: 'cancel',
                onTap: () => setState(() => _editingCookie = null),
                color: TColors.comment,
                bordered: true,
              ),
              SizedBox(width: 8),
              TermButton(
                label: 'save',
                onTap: _saveCookie,
                color: TColors.green,
                bordered: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 10)),
        SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(border: Border.all(color: TColors.border)),
          child: TextField(
            controller: ctrl,
            enabled: enabled,
            style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: InputBorder.none,
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(color: TColors.comment, fontFamily: 'monospace', fontSize: 11),
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
      ],
    );
  }

  Widget _checkbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: value ? TColors.green : TColors.mutedText),
          SizedBox(width: 4),
          Text(label, style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (_editingCookie == null) ...[
            TermButton(
              label: 'add cookie',
              icon: Icons.add,
              onTap: _startAddCookie,
              color: TColors.green,
              bordered: true,
            ),
            SizedBox(width: 8),
            TermButton(
              label: 'import',
              icon: Icons.file_download_outlined,
              onTap: _importNetscape,
              color: TColors.cyan,
              bordered: true,
            ),
          ],
          Spacer(),
          if (_activeJar != null && _activeJar!.cookies.isNotEmpty && _editingCookie == null)
            TermButton(
              label: 'clear all',
              onTap: _clearAllCookies,
              color: TColors.red,
              bordered: true,
            ),
        ],
      ),
    );
  }

  Future<String?> _showNameDialog(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title, style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
        content: Container(
          decoration: BoxDecoration(border: Border.all(color: TColors.border)),
          child: TextField(
            controller: ctrl,
            style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: InputBorder.none,
              isDense: true,
              hintText: 'jar name',
              hintStyle: TextStyle(color: TColors.comment, fontFamily: 'monospace', fontSize: 11),
            ),
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel', style: TextStyle(color: TColors.mutedText, fontSize: 12))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('create', style: TextStyle(color: TColors.green, fontSize: 12))),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }
}
