import 'dart:convert';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/domain/models/diff_entry.dart';
import 'package:curel/domain/services/diff/response_diff_engine.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
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

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: entries.length,
      itemBuilder: (context, index) => _DiffCard(entry: entries[index]),
    );
  }
}

class _DiffCard extends StatelessWidget {
  final DiffEntry entry;

  const _DiffCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (Color bg, String label) = switch (entry.type) {
      DiffType.added => (TColors.green.withValues(alpha: 0.1), '+'),
      DiffType.removed => (TColors.red.withValues(alpha: 0.1), '-'),
      DiffType.changed => (TColors.orange.withValues(alpha: 0.1), '~'),
      DiffType.unchanged => (TColors.mutedText.withValues(alpha: 0.05), ' '),
    };

    return Container(
      margin: EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: _typeColor(entry.type), width: 3),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _typeColor(entry.type),
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.path,
                    style: TextStyle(
                      color: TColors.cyan,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            if (entry.type == DiffType.changed) ...[
              _valueBlock('a', entry.formattedValueA, TColors.red),
              SizedBox(height: 2),
              _valueBlock('b', entry.formattedValueB, TColors.green),
            ] else if (entry.type == DiffType.added)
              _valueBlock('b', entry.formattedValueB, TColors.green)
            else if (entry.type == DiffType.removed)
              _valueBlock('a', entry.formattedValueA, TColors.red),
          ],
        ),
      ),
    );
  }

  Color _typeColor(DiffType type) {
    return switch (type) {
      DiffType.added => TColors.green,
      DiffType.removed => TColors.red,
      DiffType.changed => TColors.orange,
      DiffType.unchanged => TColors.mutedText,
    };
  }

  Widget _valueBlock(String side, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: TColors.background,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class CompareSourceDialog extends StatefulWidget {
  final CurlResponse currentResponse;

  const CompareSourceDialog({required this.currentResponse, super.key});

  @override
  State<CompareSourceDialog> createState() => _CompareSourceDialogState();
}

class _CompareSourceDialogState extends State<CompareSourceDialog> {
  final _urlController = TextEditingController();
  bool _loading = false;
  CurlResponse? _targetResponse;
  String? _error;
  List<DiffEntry>? _diffEntries;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _doCompare() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _targetResponse = null;
      _diffEntries = null;
    });

    try {
      final httpClient = DioCurlHttpClient();
      final curlText = 'curl "$url"';
      final parsed = parseCurl(curlText);
      final result = await httpClient.execute(
        parsed.curl,
        verbose: false,
        followRedirects: true,
      );

      final engine = JsonDiffEngine();
      final bodyA = _parseJsonBody(widget.currentResponse.bodyText);
      final bodyB = _parseJsonBody(result.bodyText);
      final entries = engine.diff(bodyA, bodyB);

      setState(() {
        _targetResponse = result;
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
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: double.maxFinite,
        child: _diffEntries != null && _targetResponse != null
            ? _DiffResultView(
                entries: _diffEntries!,
                responseA: widget.currentResponse,
                responseB: _targetResponse!,
                onBack: () => setState(() {
                  _targetResponse = null;
                  _diffEntries = null;
                  _error = null;
                }),
              )
            : _InputView(
                urlController: _urlController,
                loading: _loading,
                error: _error,
                onCompare: _doCompare,
                onCancel: () => Navigator.of(context).pop(),
              ),
      ),
    );
  }
}

class _InputView extends StatelessWidget {
  final TextEditingController urlController;
  final bool loading;
  final String? error;
  final VoidCallback onCompare;
  final VoidCallback onCancel;

  const _InputView({
    required this.urlController,
    required this.loading,
    this.error,
    required this.onCompare,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'compare with',
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: TColors.surface,
            child: TextField(
              controller: urlController,
              autofocus: true,
              cursorColor: TColors.green,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'https://api.example.com/data',
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
              onSubmitted: (_) => onCompare(),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              error!,
              style: TextStyle(
                color: TColors.red,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TermButton(
                label: 'cancel',
                onTap: onCancel,
              ),
              SizedBox(width: 8),
              TermButton(
                label: loading ? 'fetching…' : 'compare',
                onTap: loading ? null : onCompare,
              ),
            ],
          ),
        ),
        if (loading)
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TColors.green,
              ),
            ),
          ),
      ],
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
      mainAxisSize: MainAxisSize.min,
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
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 400),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (context, index) => _DiffCard(entry: entries[index]),
          ),
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
