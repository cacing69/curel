import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/workspace_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class ImportResult {
  final String? projectId;
  final String? customName;

  const ImportResult({this.projectId, this.customName});
}

class ImportPreviewDialog extends StatefulWidget {
  final PreviewResult preview;
  final List<Project> projects;

  const ImportPreviewDialog({
    required this.preview,
    this.projects = const [],
    super.key,
  });

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  String? _selectedProjectId;
  late TextEditingController _nameController;
  late ScrollController _scrollController;
  int _visibleCount = 20;
  static const _pageSize = 20;

  late List<ImportedRequest> _requests;
  late Set<String> _detectedVars;
  late Map<String, int> _methodCounts;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.preview.collection.name,
    );
    _scrollController = ScrollController()..addListener(_onScroll);

    _requests = widget.preview.collection.requests;
    _detectedVars = _scanVariables(_requests);
    _methodCounts = _countMethods(_requests);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      if (_visibleCount < _requests.length) {
        setState(() => _visibleCount += _pageSize);
      }
    }
  }

  bool get _isNewProject => _selectedProjectId == null;

  // ── Data extraction helpers ──────────────────────────────────────

  static Set<String> _scanVariables(List<ImportedRequest> requests) {
    final vars = <String>{};
    final regex = RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>');
    for (final r in requests) {
      regex.allMatches(r.curlContent).forEach((m) => vars.add(m.group(1)!));
    }
    return vars;
  }

  static Map<String, int> _countMethods(List<ImportedRequest> requests) {
    final counts = <String, int>{};
    for (final r in requests) {
      final method = _extractMethod(r.curlContent);
      counts[method] = (counts[method] ?? 0) + 1;
    }
    return counts;
  }

  static String _extractMethod(String curl) {
    final m = RegExp(r'curl\s+(?:\\\s+)?(?:-X\s+)?(\w+)').firstMatch(curl);
    if (m != null) {
      final method = m.group(1)!.toUpperCase();
      if (method != 'CURLOPT' &&
          method != 'D' &&
          method != 'H' &&
          method != 'F' &&
          method != 'A') {
        return method;
      }
    }
    return 'GET';
  }

  static String _extractEndpoint(String curl) {
    // Last single-quoted string in the curl content
    final matches = RegExp(
      r"'([^']*)'",
    ).allMatches(curl.split('\\\n').join(' '));
    final last = matches.isNotEmpty ? matches.last.group(1) : null;
    if (last != null && last.isNotEmpty) {
      // Strip query params for display
      final qPos = last.indexOf('?');
      return qPos > 0 ? last.substring(0, qPos) : last;
    }
    return '';
  }

  static Color _methodColor(String method) {
    return switch (method) {
      'GET' => TColors.green,
      'POST' => TColors.cyan,
      'PUT' => TColors.orange,
      'PATCH' => TColors.yellow,
      'DELETE' => TColors.red,
      'HEAD' => TColors.mutedText,
      _ => TColors.foreground,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = widget.preview.collection;
    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: BoxConstraints(maxWidth: 360, maxHeight: 520),
        decoration: BoxDecoration(border: Border.all(color: TColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Container(height: 1, color: TColors.border),
            Flexible(child: _body(c)),
            Container(height: 1, color: TColors.border),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: TColors.surface,
      child: Row(
        children: [
          Icon(Icons.upload_file, size: 14, color: TColors.green),
          SizedBox(width: 6),
          Text(
            'import collection',
            style: TextStyle(
              color: TColors.green,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.close, size: 14, color: TColors.comment),
          ),
        ],
      ),
    );
  }

  Widget _body(ImportedCollection c) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _targetSelector(c.name),
          SizedBox(height: 8),
          Container(height: 1, color: TColors.border),
          SizedBox(height: 8),
          _row('source', widget.preview.adapterName),
          _row('name', c.name),
          if (c.description != null && c.description!.isNotEmpty)
            _row('desc', c.description!),
          if (_requests.isNotEmpty) ...[
            SizedBox(height: 8),
            _buildSummaryRow(),
            SizedBox(height: 6),
            ...List.generate(
              _requests.length < _visibleCount
                  ? _requests.length
                  : _visibleCount,
              (i) => _buildRequestRow(_requests[i]),
            ),
            if (_visibleCount < _requests.length)
              _more(_requests.length - _visibleCount),
          ],
          if (_detectedVars.isNotEmpty) ...[
            SizedBox(height: 8),
            _sectionHeader(
              'detected variables',
              _detectedVars.length,
              TColors.purple,
            ),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: _detectedVars
                  .map(
                    (v) => Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: TColors.purple.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        v,
                        style: TextStyle(
                          color: TColors.purple,
                          fontFamily: 'monospace',
                          fontSize: 9,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (c.environments.isNotEmpty) ...[
            SizedBox(height: 8),
            _sectionHeader(
              'environments',
              c.environments.length,
              TColors.orange,
            ),
            ...c.environments.map(
              (e) => _item('${e.name} (${e.variables.length} vars)'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final parts = _methodCounts.entries.map(
      (e) => '${e.key.toLowerCase()}:${e.value}',
    );
    return Row(
      children: [
        Text(
          'requests',
          style: TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(width: 4),
        Text(
          '${_requests.length}',
          style: TextStyle(
            color: TColors.cyan.withValues(alpha: 0.7),
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: TextStyle(
              color: TColors.comment,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRequestRow(ImportedRequest r) {
    final method = _extractMethod(r.curlContent);
    final endpoint = _extractEndpoint(r.curlContent);
    final color = _methodColor(method);
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              method,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              endpoint.isNotEmpty ? endpoint : r.path.replaceAll('.curl', ''),
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetSelector(String collectionName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'import to',
          style: TextStyle(
            color: TColors.green,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        _targetOption(null, 'new project'),
        if (_isNewProject) ...[SizedBox(height: 4), _buildNameField()],
        if (widget.projects.isNotEmpty)
          ...widget.projects.map((p) => _targetOption(p.id, p.name)),
      ],
    );
  }

  Widget _buildNameField() {
    return Container(
      margin: EdgeInsets.only(left: 18, bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: TColors.border),
        color: TColors.background,
      ),
      child: TextField(
        controller: _nameController,
        cursorColor: TColors.green,
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
        decoration: InputDecoration(
          hintText: 'project name',
          hintStyle: TextStyle(
            color: TColors.comment,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
      ),
    );
  }

  Widget _targetOption(String? id, String label) {
    final selected = _selectedProjectId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedProjectId = id),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: EdgeInsets.only(bottom: 2),
        color: selected ? TColors.surface : Colors.transparent,
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 12,
              color: selected ? TColors.green : TColors.comment,
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? TColors.green : TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: TColors.comment,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, bottom: 1),
      child: Text(
        '▸ $text',
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _more(int count) {
    return Padding(
      padding: EdgeInsets.only(left: 8),
      child: Text(
        '... +$count more',
        style: TextStyle(
          color: TColors.comment,
          fontFamily: 'monospace',
          fontSize: 10,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: TColors.surface,
      child: Row(
        children: [
          Spacer(),
          TermButton(
            label: 'cancel',
            onTap: () => Navigator.of(context).pop(),
            color: TColors.comment,
            bordered: true,
          ),
          SizedBox(width: 6),
          TermButton(
            label: 'import',
            onTap: () {
              Navigator.of(context).pop(
                ImportResult(
                  projectId: _selectedProjectId,
                  customName: _isNewProject
                      ? _nameController.text.trim()
                      : null,
                ),
              );
            },
            color: TColors.green,
            bordered: true,
          ),
        ],
      ),
    );
  }
}
