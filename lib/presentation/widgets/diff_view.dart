import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/domain/models/diff_entry.dart';
import 'package:curel/domain/models/request_item_model.dart';
import 'package:curel/domain/services/diff/response_diff_engine.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/curl_highlight_controller.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class DiffView extends StatelessWidget {
  final List<DiffEntry> entries;
  final CurlResponse responseA;
  final CurlResponse responseB;

  const DiffView({
    required this.entries,
    required this.responseA,
    required this.responseB,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      appBar: _buildAppBar(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryBar(),
          Container(height: 1, color: TColors.border),
          Expanded(child: _buildDiffList()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(36),
      child: Container(
        color: TColors.surface,
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
              ),
              SizedBox(width: 8),
              Text(
                'diff',
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final added = entries.where((e) => e.type == DiffType.added).length;
    final removed = entries.where((e) => e.type == DiffType.removed).length;
    final changed = entries.where((e) => e.type == DiffType.changed).length;

    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _summaryChip('$added added', TColors.green),
          SizedBox(width: 8),
          _summaryChip('$removed removed', TColors.red),
          SizedBox(width: 8),
          _summaryChip('$changed changed', TColors.orange),
          if (entries.isEmpty) ...[
            SizedBox(width: 8),
            Text(
              'no differences',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildDiffList() {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'responses are identical',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }

    return _UnifiedDiffView(entries: entries);
  }
}

class CompareSourceDialog extends StatefulWidget {
  final String baseCurlText;
  final String projectId;
  final CurlResponse? currentResponse;
  final RequestService requestService;

  const CompareSourceDialog({
    required this.baseCurlText,
    required this.projectId,
    required this.requestService,
    this.currentResponse,
    super.key,
  });

  @override
  State<CompareSourceDialog> createState() => _CompareSourceDialogState();
}

class _CompareSourceDialogState extends State<CompareSourceDialog> {
  final _baseCurlController = TextEditingController();
  final _searchController = TextEditingController();
  List<RequestItem> _requests = [];
  bool _loading = false;
  bool _loadingRequests = true;
  bool _showRequests = false;
  CurlResponse? _targetResponse;
  CurlResponse? _baseResponse;
  String? _error;
  List<DiffEntry>? _diffEntries;

  List<RequestItem> get _filteredRequests {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return _requests;
    return _requests.where((r) =>
      r.displayName.toLowerCase().contains(q) ||
      r.relativePath.toLowerCase().contains(q) ||
      r.method.toLowerCase().contains(q)
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _baseCurlController.text = widget.baseCurlText;
    _searchController.addListener(() => setState(() {}));
    _loadRequests();
  }

  void _onCurlChanged(String text) {
    _baseCurlController.text = text;
  }

  @override
  void dispose() {
    _baseCurlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurlFromRequest(RequestItem req) async {
    try {
      final content = await widget.requestService.readCurl(
        widget.projectId, req.relativePath);
      if (content != null && mounted) {
        _baseCurlController.text = content;
      }
    } catch (_) {}
  }

  Future<void> _loadRequests() async {
    try {
      final items = await widget.requestService.listRequests(widget.projectId);
      if (mounted) setState(() {
        _requests = items;
        _loadingRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _doCompare() async {
    setState(() {
      _loading = true;
      _error = null;
      _targetResponse = null;
      _baseResponse = null;
      _diffEntries = null;
    });

    try {
      final httpClient = DioCurlHttpClient();

      final baseText = _baseCurlController.text.trim();
      if (!baseText.startsWith('curl')) {
        setState(() { _loading = false; _error = 'command must start with "curl"'; });
        return;
      }
      ParsedCurl parsed;
      try {
        parsed = parseCurl(baseText);
      } catch (_) {
        setState(() { _loading = false; _error = 'failed to parse curl command'; });
        return;
      }
      final newResponse = await httpClient.execute(parsed.curl);

      final engine = JsonDiffEngine();
      final bodyA = _parseJsonBody(widget.currentResponse?.bodyText ?? '');
      final bodyB = _parseJsonBody(newResponse.bodyText);
      final entries = engine.diff(bodyA, bodyB);

      setState(() {
        _baseResponse = widget.currentResponse;
        _targetResponse = newResponse;
        _diffEntries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  dynamic _parseJsonBody(String body) {
    try { return jsonDecode(body); } catch (_) { return body; }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.1,
        vertical: size.height * 0.1,
      ),
      child: SizedBox(
        width: double.maxFinite,
        height: size.height * 0.8,
        child: _diffEntries != null && _targetResponse != null
            ? _DiffResultView(
                entries: _diffEntries!,
                responseA: _baseResponse ?? widget.currentResponse!,
                responseB: _targetResponse!,
                onBack: () => setState(() {
                  _targetResponse = null;
                  _baseResponse = null;
                  _diffEntries = null;
                  _error = null;
                }),
              )
            : _buildInput(),
      ),
    );
  }

  Widget _buildInput() {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'compare request',
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
        // Editable base curl — with syntax highlighting
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: TColors.surface,
              child: _CurlEditor(
                initialText: widget.baseCurlText,
                onChanged: _onCurlChanged,
              ),
            ),
          ),
        ),
        SizedBox(height: 10),
        // Saved requests — tap to load curl into editor
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => setState(() => _showRequests = !_showRequests),
            child: Row(
              children: [
                Icon(
                  _showRequests ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: TColors.mutedText,
                ),
                SizedBox(width: 4),
                Text(
                  'load from saved request',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showRequests) ...[
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _buildSearchField(),
          ),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _buildSavedRequestList(),
          ),
        ],
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              _error!,
              style: TextStyle(color: TColors.red, fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TermButton(
                label: 'cancel',
                onTap: () => Navigator.of(context).pop(),
              ),
              SizedBox(width: 8),
              TermButton(
                label: _loading ? 'comparing…' : 'compare',
                onTap: _loading ? null : _doCompare,
              ),
            ],
          ),
        ),
        if (_loading)
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Center(
              child: Text(
                'comparing...',
                style: TextStyle(
                  color: TColors.green,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: TColors.surface,
      child: TextField(
        controller: _searchController,
        cursorColor: TColors.green,
        style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 11),
        decoration: InputDecoration(
          hintText: 'search requests…',
          hintStyle: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 11),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSavedRequestList() {
    if (_loadingRequests) {
      return SizedBox(
        height: 32,
        child: Center(
          child: Text(
            'loading...',
            style: TextStyle(
              color: TColors.mutedText,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ),
      );
    }

    final filtered = _filteredRequests;
    return Container(
      constraints: BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: TColors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: filtered.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'no matches',
                  style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
        itemBuilder: (context, index) {
          final req = filtered[index];
          final folder = _folderPath(req.relativePath);
          return GestureDetector(
            onTap: () {
              _loadCurlFromRequest(req);
              setState(() => _showRequests = false);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  _methodLabel(req.method),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          req.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: TColors.foreground,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (folder.isNotEmpty)
                          Text(
                            folder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: TColors.mutedText,
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _folderPath(String relativePath) {
    final posix = relativePath.replaceAll('\\', '/');
    final slash = posix.lastIndexOf('/');
    return slash >= 0 ? posix.substring(0, slash) : '';
  }

  Widget _methodLabel(String method) {
    final color = switch (method) {
      'GET' => TColors.green,
      'POST' => TColors.cyan,
      'PUT' => TColors.orange,
      'PATCH' => TColors.yellow,
      'DELETE' => TColors.red,
      'HEAD' => TColors.mutedText,
      'OPTIONS' => TColors.mutedText,
      _ => TColors.foreground,
    };
    return SizedBox(
      width: 38,
      child: Text(
        method.isEmpty ? '' : method.padRight(4).substring(0, 4).toUpperCase(),
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _UnifiedDiffView extends StatelessWidget {
  final List<DiffEntry> entries;

  const _UnifiedDiffView({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) => _UnifiedDiffLine(entry: entries[index]),
    );
  }
}

class _UnifiedDiffLine extends StatelessWidget {
  final DiffEntry entry;

  const _UnifiedDiffLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final path = entry.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // @@ header
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: TColors.cyan.withValues(alpha: 0.08),
          child: Text(
            '@@ $path @@',
            style: TextStyle(
              color: TColors.cyan,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ),
        // removed/changed A side
        if (entry.type == DiffType.removed || entry.type == DiffType.changed)
          _line(entry.formattedValueA, TColors.red, '-'),
        // added/changed B side
        if (entry.type == DiffType.added || entry.type == DiffType.changed)
          _line(entry.formattedValueB, TColors.green, '+'),
        SizedBox(height: 2),
      ],
    );
  }

  Widget _line(String text, Color color, String prefix) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((l) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        color: color.withValues(alpha: 0.06),
        child: Text(
          '$prefix${l}',
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.3,
          ),
        ),
      )).toList(),
    );
  }
}

class _DiffResultView extends StatelessWidget {
  final List<DiffEntry> entries;
  final CurlResponse responseA;
  final CurlResponse responseB;
  final VoidCallback onBack;

  const _DiffResultView({
    required this.entries,
    required this.responseA,
    required this.responseB,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final added = entries.where((e) => e.type == DiffType.added).length;
    final removed = entries.where((e) => e.type == DiffType.removed).length;
    final changed = entries.where((e) => e.type == DiffType.changed).length;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: TColors.surface,
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
              ),
              SizedBox(width: 8),
              _miniChip('+$added', TColors.green),
              SizedBox(width: 6),
              _miniChip('-$removed', TColors.red),
              SizedBox(width: 6),
              _miniChip('~$changed', TColors.orange),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: TColors.surface,
          child: Row(
            children: [
              _statusBadge(responseA.statusCode),
              SizedBox(width: 8),
              Text(
                'vs',
                style: TextStyle(color: TColors.mutedText, fontSize: 11, fontFamily: 'monospace'),
              ),
              SizedBox(width: 8),
              _statusBadge(responseB.statusCode),
            ],
          ),
        ),
        Container(height: 1, color: TColors.border),
        Expanded(
          child: _UnifiedDiffView(entries: entries),
        ),
        Padding(
          padding: EdgeInsets.all(12),
          child: TermButton(
            label: 'show full diff',
            onTap: () {
              Navigator.of(context).pop();
              _openFullDiff(context);
            },
          ),
        ),
      ],
    );
  }

  void _openFullDiff(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiffView(
          entries: entries,
          responseA: responseA,
          responseB: responseB,
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 10),
      ),
    );
  }

  Widget _statusBadge(int? code) {
    if (code == null) return SizedBox();
    final color = code >= 200 && code < 300 ? TColors.green : TColors.red;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$code',
        style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class _CurlEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;

  const _CurlEditor({
    required this.initialText,
    required this.onChanged,
  });

  @override
  State<_CurlEditor> createState() => _CurlEditorState();
}

class _CurlEditorState extends State<_CurlEditor> {
  late final CurlHighlightController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CurlHighlightController(text: widget.initialText);
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    widget.onChanged(_controller.text);
  }

  @override
  void didUpdateWidget(_CurlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != oldWidget.initialText &&
        widget.initialText != _controller.text) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 8,
      minLines: 4,
      cursorColor: TColors.green,
      style: TextStyle(
        color: TColors.cyan,
        fontFamily: 'monospace',
        fontSize: 11,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
